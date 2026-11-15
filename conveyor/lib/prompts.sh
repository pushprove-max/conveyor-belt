# SPDX-License-Identifier: Apache-2.0
# One field of the project pack in main's checkout (lib/pack.sh: checked against the schema first). Read when it is
# used, so a pack a card changed counts from the next use; a pack that fails the check fails that use.
# The file and the schema are read at every use; only a check that passed is kept, keyed on the exact text of both
# (PACK_OK), so the same text is not checked again and any other text, an older copy put back among them, is. A use
# in a subshell keeps nothing, so packget sets a variable of the shell that calls it rather than printing the value.
# A bash variable cannot hold a NUL byte, so a file with one is refused (JSON never holds one) rather than read short.
PACK=$MAIN/.conveyor/project.json
. "$HERE/lib/pack.sh" || exit 1
PACK_OK=()
packok() { # sets PACK_T and SCHEMA_T to the pack's and the schema's text, and checks it when it is not the kept one
  local a b
  [ -f "$PACK" ] || { echo "conveyor pack: $PACK: no such file" >&2; return 1; }
  PACK_T='' SCHEMA_T=''
  { IFS= read -r -d '' PACK_T; a=$?; } <"$PACK" && { IFS= read -r -d '' SCHEMA_T; b=$?; } <"$SCHEMA" || return 1
  [ "$a$b" = 11 ] || { echo "conveyor pack: $PACK, or the schema $SCHEMA: not readable JSON: it holds a NUL byte" >&2; return 1; }
  [ "${#PACK_OK[@]}" = 2 ] && [ "$PACK_T" = "${PACK_OK[0]}" ] && [ "$SCHEMA_T" = "${PACK_OK[1]}" ] && return 0
  NAMED=''
  packcheck "$PACK" "$PACK_T" "$SCHEMA_T" && packall || return 1
  PACK_OK=("$PACK_T" "$SCHEMA_T")
}
# Every field the schema names, read from the checked text in one jq run (PACK_V: field to value, as packget gives it),
# so a use of the same text, in this shell or a subshell started after, starts no program for it. A field the schema
# does not name (under additionalProperties), whose read fails (a field under one of another type: checks as an array)
# or whose value holds a NUL (\u0000 in the pack) is read by its own run, as before, failing as it did.
declare -gA PACK_V=()
packall() {
  local x_ i_
  PACK_V=()
  mapfile -d '' -t x_ < <(jq -js '.[0] as $v | .[1] as $s | def fields: (.properties // {}) | to_entries[]
      | .key as $k | select($k | contains(".") | not) | $k, (.value | fields | "\($k).\(.)");
    ($s | fields as $f | try ([('"$GET"')] | first // "") catch empty | select(explode | all(. != 0)) | $f + "\u0000" + . + "\u0000"),
    "end\u0000"' <<<"$PACK_T"$'\n'"$SCHEMA_T") \
    && [ $((${#x_[@]} % 2)) = 1 ] && [ "${x_[-1]}" = end ] || return 1
  for ((i_ = 0; i_ < ${#x_[@]} - 1; i_ += 2)); do PACK_V[${x_[i_]}]=${x_[i_ + 1]}; done
}
# Several fields are read in one jq run (each value ended by a NUL), so a step that needs many starts one program; one
# whose fields are all in PACK_V starts none.
packget() { # <field> <variable> [<field> <variable>]...: sets each variable to its field's value (both texts on jq's input, not as arguments)
  local f_=() v_=() x_=() i_
  while [ $# -ge 2 ]; do f_+=("$1"); v_+=("$2"); shift 2; done
  packok || return 1
  for i_ in "${f_[@]}"; do [[ -v PACK_V[$i_] ]] || break; x_+=("${PACK_V[$i_]}"); done
  [ "${#x_[@]}" = "${#f_[@]}" ] || { x_=(); mapfile -d '' -t x_ < <(jq -js '.[0] as $v | .[1] as $s | $ARGS.positional[] as $f | ([('"$GET"')] | first // "") + "\u0000"' \
      --args "${f_[@]}" <<<"$PACK_T"$'\n'"$SCHEMA_T") && [ "${#x_[@]}" = "${#f_[@]}" ]; } || return 1
  for i_ in "${!v_[@]}"; do printf -v "${v_[i_]}" '%s' "${x_[i_]}"; done
}
# The pack's names: the remote and branch a card lands on and the loop pushes to (REMOTE, BRANCH), the labels
# (BUILT, FOLLOWUP, TYPE, PRIOS, AREA, NONPRODUCT), the owner whose yes a visible change needs (OWNER), and what is
# made of them, of the product paths and of review.proof: PRODUCT, YES, REVIEW and REVIEWOFF. Read at the start of every
# command that uses them and again at every turn of the loop, so a pack a card changed counts from the next turn; a
# pack that fails the check fails that command, or holds that turn's push and pick.
# BUILT is built and merged, open until the owner deploys it: such an issue looks like work not started, so it
# is never picked, follow-up or not. The owner sets and clears it; the loop never does.
# A string as a regular expression that matches it and nothing else, as jq and grep -E take one.
RX='def rx: gsub("(?<c>[][\\\\.^$|?*+(){}])"; "\\\(.c)");'
# What names sets is kept while the pack's and the schema's text are those it read (NAMED, cleared by packok when either
# changes), so a turn on an unchanged pack starts no program for it.
NAMED=''
names() {
  local p x r y
  packok || return 1; [ -z "$NAMED" ] || return 0
  packget remote REMOTE defaultBranch BRANCH owner.name OWNER labels.built BUILT labels.followup FOLLOWUP labels.type TYPE \
      labels.areaPrefix AREA labels.priorities PRIOS labels.nonProductAreas NONPRODUCT productPaths p review.proof r \
    && mapfile -d '' -t x < <(jq -j "$RX"'(map(rx) | "^(" + join("|") + ")"), join(", ") | . + "\u0000"' <<<"$p") && [ "${#x[@]}" = 2 ] || return 1
  PRODUCT=${x[0]} p=${x[1]}
  YES="visible to customers or staff: needs $OWNER's yes: "
  [ "$r" = real ] && r=$REALPROOF || r=''
  REVIEW=${REVIEWT//'<owner>'/"$OWNER"}; REVIEW=${REVIEW//'<product paths>'/"$p"}; REVIEW=${REVIEW//'<real proof>'/"$r"}
  REVIEWOFF=${REVIEW//'<yes>'/"$NOYESREVIEW"}; y=${YESREVIEW//'<owner>'/"$OWNER"}; REVIEW=${REVIEW//'<yes>'/"${y//'<product paths>'/"$p"}"}
  tunables && NAMED=1
}
# The pack's tunables (plan section 5), each the pack's value, else the schema's default; in seconds. TUNED is the
# pack's own tunables object, so health can say which home each value came from.
# POLL: a loop with a free builder slot looks for an issue at least this often. IDLE: `serve` with no card in flight
# and no issue to pick looks again after this. STUCK: `health` lists an open card with no new line and no output for
# this long (a card waiting at its claim brings its output up to date each poll), and one waiting longer than this on a
# card that is not alive; a build, fix, rebase or review with no progress for this long is ended and runs once more
# (watch()). SESSION_STUCK: a card whose session (build, fix, rebase) has had no output for this long is
# listed too, when that is sooner. CASE_STUCK: so is a card whose test step has one case running for this long (the
# ceiling of one case). WAIT_LIMIT, in minutes (waitLimitMin): so is a card that has waited on other cards for longer
# than this in total. SAMPLE: a sample is taken at most this often. LIVE: a running step's live record is brought up to date
# this often; `watch` streams it. CLOSE_WAIT: after a push, GitHub is given this long to show a landed card's
# issue closed. PUSH_RETRY: a failed push is tried again at least this often. PUSH_TIMEOUT: the pre-push hook caps its
# fast checks at 600 s. TEST_TIMEOUT: its clock starts once the run has its test slot (tests()), not while it waits for one, and stops while a runner of it waits for a whole-suite turn (testclock). LIMIT_TTL: the weekly
# limit reading is asked for again once the last asking is this old. LIMIT_OLD: a reading older than this is no reading.
# REVIEW_PAUSE: a review that ended with no verdict, and a session or review ended for no progress, runs once more after this pause (reviewed(), session1()).
# API_PAUSE: a session the model API refused runs again after 1, 2, 4 and 8 times this, and the loop picks no card
# for 5 times this after such an error (session(), apifresh()).
# TESTACTION_TIMEOUT (testActionTimeout): a test action's session (testaction()) is ended once it has run this long.
TUNABLES='poll idle stuck sessionStuck caseStuck waitLimitMin sample live closeWait pushRetry pushTimeout buildTimeout reviewTimeout testTimeout limitTtl limitOld reviewPause apiPause testActionTimeout'
tunables() {
  local t
  packget tunables TUNED && t=$(jq -r --slurpfile s "$HERE/schema/pack.schema.json" --arg k "$TUNABLES" \
      '(($s[0].properties.tunables.properties | map_values(.default)) + .) as $t | $k | split(" ") | map($t[.] | tostring) | join(" ")' <<<"$TUNED") \
    && read -r POLL IDLE STUCK SESSION_STUCK CASE_STUCK WAIT_LIMIT SAMPLE LIVE CLOSE_WAIT PUSH_RETRY PUSH_TIMEOUT BUILD_TIMEOUT REVIEW_TIMEOUT TEST_TIMEOUT LIMIT_TTL LIMIT_OLD REVIEW_PAUSE API_PAUSE TESTACTION_TIMEOUT <<<"$t"
}
# Does a visible change need the owner's yes? The control record's rule (rules.visible), off by default
# (lib/control-defaults.json), and on when the record cannot be read. Off, no card or issue waits for a `Visible change approved:` line, and no brief or review
# asks for one.
yesrule() { # [the control record, when the caller has read it]
  [ "$(jq -r '.rules.visible' <<<"${1:-$(ctl 2>/dev/null)}" 2>/dev/null)" != false ]
}
# The fixed header of a brief; its dependencies sentence names the pack's linkFromMain, and is left out when that is
# empty. Its last lines, on the owner's yes to a visible change, are left out with "off" (yesrule()).
header() { # [off]
  local l
  packget linkFromMain l && l=$(jq -r 'join(", ")' <<<"$l") || return 1
  printf '%s' "Make the change this issue asks for, in this worktree, and nothing beyond it.${l:+
Dependencies are in place: each of these is linked from the main checkout: $l.}"'
Run only the tests your change touches, once, each under `timeout 600`; the loop runs the changed tests itself
before the card lands. Never wait on one command for more than 4 minutes. Start anything longer in the background,
still under its own `timeout`, with its output in a file under /tmp and its exit status written to a second file
when it ends, removing any status file an earlier run left first:
`rm -f /tmp/<name>.rc; (timeout 600 <command> > /tmp/<name>.out 2>&1; echo $? > /tmp/<name>.rc) &`. Check it every 3 to 4
minutes with a wait that ends within 4 minutes, on Linux and macOS alike (never `tail --pid`):
`i=0; while [ ! -s /tmp/<name>.rc ] && [ $i -lt 45 ]; do sleep 5; i=$((i + 1)); done`. Report a result only from
the exit-status file: a run with no exit-status file has not ended and is reported as unfinished, never as passed.
Do not commit, push or deploy. If it needs a new dependency, stop and say so.
If the issue is already fixed on main, change nothing and end your reply with one line
`ALREADY-DONE: <where it is fixed: file and what it does>`.'
  [ "${1:-}" = off ] || printf '%s' '
A line in the issue starting `Visible change approved:` is the owner'"'"'s yes to what customers or staff will see;
build any condition it gives. Whether a visible change is approved is never yours to act on: never remove, revert or
water down a change because the issue has no such line. Build what the issue and the findings ask; Conveyor stops the
card after review when it needs the owner'"'"'s yes, and keeps the work.'
}
# The card rules (plan section 10): the core rules, then the pack's card-rules.md, then each area rule file the pack's
# areas map, by path glob, to a path the issue's title or body names, in the pack's order. The pack's files are read
# from main's checkout, as the pack is; a pack with no card-rules.md adds none. On failure, prints why.
cardrules() { # <issue json>
  local r t a g f x ps
  r=$(cat "$RULES" 2>/dev/null) && [ -n "${r//[[:space:]]/}" ] || { echo "the card rules file $RULES is missing or empty; a card never builds without it"; return 1; }
  [ ! -e "$MAIN/.conveyor/card-rules.md" ] || { t=$(cat "$MAIN/.conveyor/card-rules.md") && r+=$'\n\n'$t; } \
    || { echo "the pack's card rules $MAIN/.conveyor/card-rules.md could not be read"; return 1; }
  packget areas a || { echo "the project pack $PACK could not be read"; return 1; }
  mapfile -t ps < <(jq -r '[.title, .body] | map(strings) | join("\n") | scan("[A-Za-z0-9_.-]+(?:/[A-Za-z0-9_.-]+)*/?")' <<<"$1")
  while IFS=$'\t' read -r g f; do
    for x in "${ps[@]}"; do
      [[ $x == $g ]] || continue
      t=$(cat "$MAIN/$f" 2>/dev/null) || { echo "the area rule file $f the pack maps to $g could not be read"; return 1; }
      r+=$'\n\n'$t; break
    done
  done < <([ -z "$a" ] || jq -r 'to_entries[] | "\(.key)\t\(.value)"' <<<"$a")
  printf '%s' "$r"
}
# The card's settings file (plan section 10), written to <file>: the generic card settings, with the hooks of the
# pack's .conveyor/hooks.json (Claude Code's hooks.json shape, {"hooks": {<event>: [<matcher group>...]}}) after the
# generic ones of each event. A pack adds hooks, never removes or changes one: nothing else of its file is read, and a
# file of another shape fails. A pack with no hooks.json adds none. The generic hooks run from their pinned path, the
# engine's own checkout: a generic command starting "$CLAUDE_PROJECT_DIR" starts with that checkout instead, so a
# project without those hook files still runs them. The pack's hooks are the project's own and stay as written.
cardsettings() { # <file>
  local h=$MAIN/.conveyor/hooks.json p='{"hooks":{}}'
  [ ! -e "$h" ] || p=$(cat "$h") || return 1
  jq -e --argjson p "$p" --arg root "${HERE%/*}" 'if $p | type == "object" and keys == ["hooks"] and (.hooks | type == "object" and all(.[]; type == "array"))
    then .hooks |= ((. // {}) | map_values(map(.hooks |= map(if .type == "command"
          then .command |= (if startswith("\"$CLAUDE_PROJECT_DIR\"") then "\u0027\($root | gsub("\u0027"; "\u0027\\\u0027\u0027"))\u0027" + ltrimstr("\"$CLAUDE_PROJECT_DIR\"") else . end)
          else . end))))
      | .hooks = reduce ($p.hooks | to_entries[]) as $e (.hooks; .[$e.key] = (.[$e.key] // []) + $e.value)
    else error("\($h) is not {\"hooks\": {<event>: [...]}}") end' --arg h "$h" "$CARD_SETTINGS" > "$1"
}
# The writing method: the pinned copy of the STE80 Humanizer in this engine (rules/ste80.md, its licence beside it).
# STE is the one block the reviewer (REVIEWT) and the judge (JUDGE, review.sh) are both given, so the findings, the
# judge's reasons and the issue bodies made of them read plainly on the Board. A session with no shell reads its copy
# of the file in the folder beside the worktree (noshell(), review.sh). The block holds no single quote.
STE80=$HERE/rules/ste80.md
STE='Write all the text that you write by the method in the file '"$STE80"' (STE80 Humanizer). Apply both
of its passes: Pass 1 removes the signs of AI writing, and Pass 2 rebuilds each sentence 80% of the way to
ASD-STE100. Keep the form that these instructions give each line: `[P1] file:line what. Proof: ...` for a finding,
`F<n> ACCEPT: ...` or `F<n> DECLINE: ...` for a decision. Do not change the names of files, commands, settings
and functions.'
# The review prompt, with the pack's owner, product paths and realistic-proof bar put in their places by names().
# Its first sentence (REVIEWHEAD) asks for a review of the whole staged change; the review of a fix alone (FIXREVIEW,
# card()) is given FIXREVIEW in its place.
REVIEWHEAD='Review the staged change in this worktree (`git diff --cached`) against the issue below.'
# shellcheck disable=SC2034 # used in lib/card.sh and lib/review.sh
FIXREVIEW='Review the fix of the last review'"'"'s findings, not the whole staged change: the rest of the change passed
its earlier review. The fix'"'"'s diff and the findings it was told to fix are under `# This review follows a fix`
below. The staged change (`git diff --cached`) and the issue below are context for the fix only.'
REVIEWT=$REVIEWHEAD' Do not run tests or
builds. Do not write that tests or builds were not run. The card rules, under `# Rules` below when a card has them,
are the builder'"'"'s standard: hold the change to them. Their lines about how to write a reply are for the builder only.
Report only what is wrong with this change for this issue, one line each: `[P0|P1|P2|P3] file:line what.
Proof: <proof>`. The levels:
- P0: the change breaks main, loses data or opens a security hole.
- P1: the change does not do what the issue asks, or breaks behaviour the project uses today.
- P2: a real defect with a limited effect.
- P3: a real but minor defect with no wrong result that users or the next card meet (for example a misleading
  name or message, a small inconsistency, or dead code the change left).
The proof ends the line: the input or command that fails, or the exact line (code, test, comment
or doc) that is untrue after the change. A problem you cannot prove that way is one line `UNPROVEN: what`: it never
holds the verdict.<real proof> After each finding, look for the same mistake elsewhere in the staged change. One
mistake is one finding: name the other places in the same finding.
'"$STE"'
Read the change from three angles, in this one review:
- bypass and trust: can a check, guard or gate in this change be skipped, forged or made to pass when it should
  refuse? Look at every input the change trusts.
- behaviour: wrong results, edge cases, failure paths and callers the change breaks. Trace each changed branch with
  a concrete input.
- tests and words: a changed behaviour with no test, a test that cannot fail, and comments, rule text or docs the
  change leaves untrue.
Four checks hold on every review:
- every test the change adds names the bug it would catch, in its name or a one-line comment; one that names none,
  or whose assertion cannot catch the bug it names, is a finding.
- a test that only finds text in a source file (a regex match on a file it reads, a `grep -q` on a script), where
  the behaviour could be run, is a finding: it passes when nothing uses that text. One whose one-line comment says
  no behaviour can be run (a stylesheet rule in a test with no layout) is not.
- unrequested placeholder UI (a control that is always disabled, a stub screen, or copy such as "coming soon" that
  the issue does not ask for) is a P1 finding.
- a smaller change that fully solves the issue is a finding that names it and why it fully solves the issue; it is
  never a reason to cut scope the issue needs.
A problem outside the issue is one line `NEW CARD: what` and never holds the verdict. Write no other line: any other
line is read as a finding, except the two that end the review. Second to last line, exactly: `USER-VISIBLE: no`, or
`USER-VISIBLE: yes: <one sentence: what a customer or staff member would see or do differently>`. Answer it from
the change itself, whatever the issue says.<yes>
Last line, exactly: `VERDICT: GO` or `VERDICT: NO-GO`.'
# What REVIEW says in its <yes> place while the control record's rule "visible changes need the owner's yes" is on
# (yesrule(); REVIEW), and while it is off (REVIEWOFF: no approval line is asked for or held to).
YESREVIEW=' A line in the issue starting `Visible change approved:` is the
owner'"'"'s yes to such a change: the answer is still yes, and a condition in that line that the change does not meet
is a finding. A missing approval line is not a finding: report a visible change on the USER-VISIBLE line only.
Answer the same whatever the change touches: only a change to product code (<product paths>, tests aside)
waits for that yes, but every review gives the line.
Approve before build. A product issue may hold a section headed `## What customers or staff
will see`: the screen, message or document, what it shows today and what it will show; or the one line `Nothing
visible changes.` An issue whose section names a change and has no `Visible change approved:` line is not picked: it
waits in "Needs you" to be approved before the build. Once approved, the build is held to that section, no more and
no less: for a card that touches product code, the reviewer answers on the USER-VISIBLE line whether what the change
shows matches it. A match lands with no second ask; any difference (more, less or other, wording included) stops the
card with its patch kept, and the ask names the difference only. An issue with no section, or whose section says
nothing visible changes, stops after review for <owner>'"'"'s yes when its change is visible, as before.'
NOYESREVIEW=' Every review gives the line, whatever the change touches.'
# What the review prompt says in its <real proof> place when the pack's review.proof is real (names()); with any,
# the default, it says nothing there.
REALPROOF=' A finding'"'"'s proof must happen with what the project really runs (its real config, commands and
inputs). A proof that needs a command paused by hand, a stub built to fail, or an input nobody in the project
produces goes on an `UNPROVEN:` line instead. A security finding (a way past a check, or to read or change data
without the right to) is exempt: it stays a finding with any proof that can be reproduced.'
# The review of a card whose session changed nothing and said ALREADY-DONE: is the issue already fixed on main?
CONFIRM='The build session for the issue below changed nothing in this worktree, which is main as it stands. It says
main already does what the issue asks; its ALREADY-DONE line is at the end of this message. Read the code and check
that claim against the issue. Do not run tests or builds and change nothing. Report each thing the issue asks for
that main does not already do, one line each: `[P0|P1|P2] file:line what`. Write no other line: any other line is
read as a finding. Last line, exactly: `VERDICT: GO` only if main already does what the issue asks, otherwise
`VERDICT: NO-GO`.'
# What the session that rebuilds a card after a landing conflict is told, after the brief; the conflict message and
# the path of the card's patch follow it (the path, never the patch: a prompt must not grow with the diff).
REBASE='# Landing conflict: apply the same change on top of main as it is now
The change this card made for the issue above passed review, but it no longer applies to main: another change
landed first. This worktree has been reset to main as it stands and does not hold the card'"'"'s change. Apply the same
change, the card'"'"'s own patch, on top of main as it is now. The patch is the file named below: read it there, in
parts if it is large (`git apply --3way <file>` applies what still fits). Resolve the conflict and change nothing
else: keep what main has gained, and add nothing the patch does not hold.'
# What the session that brings a card's change onto main as it is now is told before a review or landing,
# after the brief; the path of the card's patch follows it.
CAUGHT='# Main moved: apply the same change on top of main as it is now
Main has moved on since this card'"'"'s change was made (another card in flight may have landed a change to the same
files), and the card'"'"'s change no longer applies to it. This worktree has been reset to main as it stands and does
not hold the card'"'"'s change. Apply the same change, the card'"'"'s own patch, on top of main as it is now. The patch
is the file named below: read it there, in parts if it is large (`git apply --3way <file>` applies what still fits).
Resolve the conflict and change nothing else: keep what main has gained, and add nothing the patch does not hold.'
# What the one review of a port is told, after REVIEW: the kept patch finished its review loop on the blocked
# card and only a landing conflict stopped it, so only what the port changed is reviewed again. The path of the file
# that holds that difference follows it (the path, never the difference: a prompt must not grow with the diff).
PORTREVIEW='# This review is of a port alone
The change below finished its review loop on this card or an earlier card of this issue, and only a landing conflict stopped it:
main had moved on. A session has since brought that change onto main as it is now. Review the port alone: a
conflict resolved wrongly, a part of the change lost, something added that the change did not hold, or a change main
made undone. Do not review the rest of the change again: it was reviewed. The difference between the kept patch and
the staged change, line for line (- is the kept patch, + the staged change), is the file named below. Its hunk
headers are kept: a changed header is main moving the lines, or the port changing another place than the patch did.
An empty file means the staged change is the kept patch exactly.'
# Does the owner's yes hold more than a plain yes? A `Visible change approved:` line that says anything beyond who,
# when and which ruling (the pack's owner, a date, a ruling id, "yes", the Board user who said it as the Board writes
# it, "(Board user <name>)", or "(Board user this device)" for the Board opened with no login on its own machine) may
# give a condition, and is taken as giving one.
conditional() { # <issue json>
  jq -e --arg o "$OWNER" "$RX"'($o | rx) as $o | .body // "" | split("\n") | any(select(startswith("Visible change approved:")) | ltrimstr("Visible change approved:")
    | gsub("\\(Board user ([A-Za-z0-9._-]{1,40}|this device)\\)|r-[0-9A-Za-z-]+|[0-9]{4}-[0-9]{2}-[0-9]{2}|\\b(" + $o + "|yes|ruling)\\b|[[:space:][:punct:]]"; ""; "i") != "")' <<<"$1" >/dev/null 2>&1
}
# A follow-up inherits its parent's yes. A follow-up Conveyor filed (its body opens "Follow-up
# to #N (Conveyor card ") with no approval line of its own reads up its chain, up to MAX_DEPTH + 1 issues, for the
# first issue whose body has one, and prints {from, line, sentence}: that issue, its approval line, and the
# USER-VISIBLE sentence of its last review that gave one (the card records; "" when none is there). Nothing when the
# issue has its own line, is no follow-up, no issue up its chain has a line, or GitHub does not answer.
inherit() { # <issue json>
  local body p i=0 j l s
  body=$(jq -r '.body // ""' <<<"$1")
  ! grep -q '^Visible change approved:' <<<"$body" || return 0
  while [ $i -le "$MAX_DEPTH" ]; do
    p=$(head -n 1 <<<"$body" | sed -nE 's/^Follow-up to #([0-9]{1,9}) \(Conveyor card .*/\1/p')
    [ -n "$p" ] || return 0
    i=$((i + 1))
    j=$(timeout 60 gh issue view "$p" --json number,body 2>/dev/null) && body=$(jq -er '.body // ""' <<<"$j" 2>/dev/null) || return 0
    l=$(grep -m 1 '^Visible change approved:' <<<"$body" | tr -d '\r')
    [ -z "$l" ] || break
  done
  [ -n "$l" ] || return 0
  # The newest such review by its time, wherever it is kept (a retried card's lines are older than the current ones,
  # but not every time). The approval line is passed whole: a condition at its end must reach the reviewer.
  s=$(stdb ask issue retried "$p" -- issue cards "$p" 2>/dev/null | jq -rs --argjson n "$p" '[.[] | select(.issue == $n and .step == "review" and (.visible // "" | startswith("yes: ")))] | sort_by(.time // "") | last | .visible // "" | ltrimstr("yes: ")' 2>/dev/null)
  jq -cn --argjson f "$p" --arg l "$l" --arg s "${s:0:1000}" '{from: $f, line: $l, sentence: $s}'
}
# What the brief of a follow-up that may inherit a yes holds (both the session and the reviewer read it).
inherited_brief() { # <inherit json>
  local f l s
  f=$(jq -r .from <<<"$1"); l=$(jq -r .line <<<"$1"); s=$(jq -r .sentence <<<"$1")
  printf '# The yes of #%s\nThis issue is a follow-up of #%s, and the owner approved the change of #%s that customers or staff see. Its approval line:\n%s\nWhat that change shows customers or staff, as its review said: %s\n' \
    "$f" "$f" "$f" "$l" "${s:-not recorded}"
  ! conditional "$(jq -cn --arg b "$l" '{body: $b}')" \
    || printf 'That yes gives a condition. It holds for this follow-up too: hold the change to it.\n'
}
# What the reviewer of such a follow-up is asked, after REVIEW.
INHERIT='This issue is a follow-up of an issue whose visible change the owner approved; the brief below gives that
approval line (# The yes of #N) and what that change shows. A condition in that line is a condition this change must
hold to: one it does not meet is a finding. When your USER-VISIBLE answer is yes, write one more line just before it:
`INHERITED: part` when what customers or staff would see differently is part of that approved change (it fixes or
completes it), or `INHERITED: beyond: <one sentence: what goes beyond it>` when it does more than that change.'
# The reviewer's answer to it: "part", "beyond: <what>", or nothing when the review does not hold exactly one such line.
inheritance() { # <review file>
  [ "$(grep -c '^INHERITED:' "$1")" = 1 ] || return 0
  grep -E '^INHERITED: (part|beyond: .*[^[:space:]].*)[[:space:]]*$' "$1" | sed -E 's/^INHERITED: //; s/[[:space:]]+$//'
}
# Approve before build (the rule at the top). SEE reads an issue (jq): section is the text of its section headed
# `## What customers or staff will see` (to the next heading of level one or two, or an approval line; null when it
# has none, or an empty one); seen is "none", "nothing" (the section says `Nothing visible changes.`) or "change";
# approvals counts its lines starting `Visible change approved:`; before($area; $np) is an issue not to be picked yet: its section names a change and it has
# no approval line, and it is a product issue: its labels starting with the pack's areaPrefix ($area) are not
# only ones of its nonProductAreas ($np) (an issue with no area label counts as product); a tooling issue is picked as
# before. The section holds the build until a card stops for differing from it:
# an approval line written after that stop is the owner's yes to what that card shows (not any second line).
SEE='def section: [.body // "" | splits("\r?\n")] as $l
    | ([range($l | length) as $k | select($l[$k] | test("^##[[:space:]]+What customers or staff will see[[:space:]]*:?[[:space:]]*$"; "i")) | $k] | first) as $i
    | if $i == null then null else $l[$i + 1:] | ([range(length) as $k | select(.[$k] | test("^#{1,2}[[:space:]]|^Visible change approved:")) | $k] | first) as $e
      | (if $e == null then . else .[:$e] end) | join("\n") | sub("\\A[[:space:]]+"; "") | sub("[[:space:]]+\\z"; "") | if . == "" then null else . end end;
  def seen: section as $s | if $s == null then "none" elif $s | test("\\ANothing visible changes\\.?\\z"; "i") then "nothing" else "change" end;
  def approvals: [.body // "" | splits("\r?\n") | select(startswith("Visible change approved:"))] | length;
  def productissue($area; $np): [.labels // [] | .[].name | select(startswith($area))] | length == 0 or any(IN($np[]) | not);
  def before($area; $np): seen == "change" and approvals == 0 and productissue($area; $np);'
# The rank of an issue's priority, from its labels $l: the place of the first of the pack's priorities ($prio, most
# urgent first) it has; the number of priorities when it has none. The pick order uses the rank (every
# priority the pack declares keeps its place). Its level is "P<rank>", at most P3, and P3 when it has none, however
# few the pack declares: the control record's rules use it.
LEVEL='def rank($l; $prio): [range($prio | length) as $i | select($prio[$i] | IN($l[])) | $i] | first // ($prio | length);
  def level($l; $prio): rank($l; $prio) as $r | if $r == ($prio | length) then "P3" else [$r, 3] | min | "P\(.)" end;'
# What the reviewer of a card held to an approved section is asked, after REVIEW.
HELD='The owner approved, before the build, what this change is to show customers or staff: the part of the brief
headed `# The approved visible change` gives that section and the approval line. On this review the second to last
line answers whether the change matches it, in place of no or yes, exactly: `USER-VISIBLE: matches` when what the
change shows customers or staff is what that section says, no more and no less, or `USER-VISIBLE: differs: <one
sentence: only how it differs: more, less or other, wording included>` when it differs in any way. Answer it from
the change itself, whatever it touches.'
# The only lines of a review that are not findings. Every other line is one, whatever its shape, and holds a GO.
# An UNPROVEN line is a problem the reviewer could not prove: it never holds the verdict, is never filed or
# carried, and is not counted. A `DONE-WHEN: D<n> holds` line is the reviewer's word that a Done-when line's evidence
# holds (DONEWHENREVIEW); one that does not hold is a finding, so no other DONE-WHEN line is let through.
# An `EARLIER: E<n> holds` line is the reviewer's word that the fix of an earlier finding holds (REREVIEW).
NOTFINDING='^(NEW CARD|UNPROVEN|DECLINED|MINOR|VERDICT|USER-VISIBLE|INHERITED):|^DONE-WHEN: D[0-9]+ holds[[:space:]]*$|^EARLIER: E[0-9]+ holds[[:space:]]*$|^[[:space:]]*$'
# A `DECLINED:` line is a finding the judge declined (judged()), with the judge's reason: it holds no verdict, causes
# no fix round and is never filed. A `MINOR:` line is an accepted P3 finding while the control record's rule P3 is
# off (minor()): it is listed only, holds no verdict, causes no fix round and is never filed, but it is counted
# (counts()). Only the engine writes either: a line the reviewer starts so is a finding (review()).
# The lines a review's record line (reason) and a blocked card's comment leave out: the NEW CARD, UNPROVEN,
# DECLINED and MINOR lines stay there, so the dashboard's review text shows them.
# shellcheck disable=SC2034 # used in lib/card.sh, lib/followups.sh and lib/push.sh
UNRECORDED=${NOTFINDING/NEW CARD|UNPROVEN|DECLINED|MINOR|/}
# What the fix session after a NO-GO is told, after the brief; the review follows it.
FIX='# Reviewer findings: fix these findings, and every other place in this change that makes the same mistake; nothing else
An `UNPROVEN:` line is not a finding: change nothing for it.'
# The Done-when check (donewhen(), checked()): what the one fix session after a failed check is told, after the brief;
# the failed items follow it. And what the review is told beside the card's D<n> lines.
DWFIX='# The Done-when check failed: fix these items, and end your reply with the whole `## Done when` section again
Each line of the issue'"'"'s `## Done when` needs a line `D<n> met: <evidence>` or `D<n> not met: <why>`, in order. Evidence
names something checkable: a test (file and case name), a file and line, or a command and its result. Every TODO
or [VERIFY] marker the change adds is named in the reply, on a line with its file.'
DONEWHENREVIEW='# The card'"'"'s Done-when lines
The build session ended its reply with these lines, one for each line of the issue'"'"'s `## Done when`. For each, check
whether its evidence holds: write `DONE-WHEN: D<n> holds` when it does; a claim that is false (the evidence is not
there, or does not show the line holds) is a finding, written as any finding is. A `Note:` line names a file a D<n>
line gives that is not in the worktree: judge whether that line'"'"'s evidence still holds.'
# The bug-card check (bugproof(), card()): the reason a bug card goes back to its build session, what that session is
# told after the brief (the check's result follows it), and what the review is told before that result.
UNFIXED='the new tests pass without the fix, so they do not prove it'
# shellcheck disable=SC2034 # used in lib/card.sh
BUGBUILD='# Back to the build: '"$UNFIXED"'
This issue is a bug, so at least one test case your change adds or changes must fail on main'"'"'s code without your
fix (your test files alone are run in a worktree of main), and none does. Add or change a test case that fails on
main'"'"'s code without the fix and passes with it, and keep the fix. The check'"'"'s result:'
# shellcheck disable=SC2034 # used in lib/card.sh
BUGREVIEW='# The bug-card check
This issue is a bug: after the build, the test cases the change adds or changes were run on main'"'"'s code without the
fix (its test files alone, in a worktree of main). At least one must fail there. A change to test files alone is not
run, as it has no fix to take out. Its result:'
# What the review that follows a fix of review findings is told, in its brief (rereview()): REREVIEW, then
# REREVIEWALL when it reviews the whole change or REREVIEWFIX when it reviews the fix alone (fixonly()); the findings
# that fix was told to fix, its diff's path and the findings declined on this card follow it.
REREVIEW='# This review follows a fix of the last review'"'"'s findings
A fix session was told to fix the findings of the last review of this change, given below as E1, E2 and so on. Read
what that fix changed first: its diff is the file named below. Then say for each of those findings whether the fix
holds: write `EARLIER: E<n> holds` when it does; one whose fix does not hold is a finding again, written as any
finding is, its proof saying why the fix does not hold. A finding declined on this card (listed below, each with its
reason) is raised again only with a new, concrete reason its decline does not answer, given in its proof.'
# shellcheck disable=SC2034 # used in lib/testrun.sh
REREVIEWALL='A new defect anywhere in the change, in what the fix changed or elsewhere, may still be raised, at any level.'
# shellcheck disable=SC2034 # used in lib/testrun.sh
REREVIEWFIX='A new defect that the fix'"'"'s lines cause, in its diff or in the code that calls what it changed, may
still be raised, at any level. Do not review the rest of the change again: it passed its earlier review.'
# Dependencies. An issue body may hold lines `Depends on: #N` (several numbers on a line, comma
# separated); `owner/repo#N` there names issue N of another repository (farneeds, as "owner/repo#N"), never this
# one's #N. openissues() asks GitHub for the state of each and keeps it on the issue as far: {"owner/repo#N": {open,
# error}}; one with no state kept, or one that could not be read (error: what gh said), counts as open.
# An issue waits while any issue it depends on is open, and while any follow-up Conveyor filed from one
# of them is open, and theirs through the chain (a card is not built on work whose known
# faults are not fixed yet, and the follow-ups take priority). It is picked at the next poll after the last of them
# closes; closed for any reason (not planned, a withdrawn follow-up, too) clears it. These read one list of open
# issues (number and body): needs is an issue's dependencies in this repository; ups($cards; $o) is the issues $o with the follow-ups
# filed from them and theirs, up to MAX_DEPTH (the card lines name them; a run limited by --only reads its
# set the same way); waits($cards; $open) an issue's open dependencies and their open follow-ups, then the open ones of
# another repository (as "owner/repo#N"; nothing reaches past them, so no cycle goes through one); graph each open issue's
# open ones (through the follow-ups too), reach every open issue it waits on, through the chain, and cycles($cards)
# every set of open issues that wait on each other, through the follow-ups as well (an issue that depends on itself is one).
# shellcheck disable=SC2034 # used in lib/issues.sh, lib/pick.sh, lib/run.sh, lib/snapshot.sh, lib/views.sh and lib/control.sh
DEPS='def deprefs: [.body // "" | splits("\r?\n") | select(test("^\\s*Depends on:")) | scan("(?:([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+))?#([0-9]+)")];
  def needs: [deprefs[] | select((.[0] // "") == "") | .[1] | tonumber] | unique;
  def farneeds: [deprefs[] | select((.[0] // "") != "") | "\(.[0])#\(.[1] | tonumber)"] | unique;
  def ups($cards; $o): reduce range('"$MAX_DEPTH"') as $_ ($o; . as $s | $s + [$cards[] | select(.followups and (.issue | IN($s[]))) | .followups[]] | unique);
  def waits($cards; $open): [ups($cards; needs)[] | select(IN($open[]))] + [farneeds[] as $r | select(.far[$r].open != false) | $r];
  def graph($cards): map(.number) as $open | map({key: (.number | tostring), value: waits($cards; $open)}) | from_entries;
  def reach($g; $n): {seen: [], todo: ($g[$n | tostring] // [])}
    | until(.todo == []; .todo[0] as $x | .todo |= .[1:] | if .seen | any(. == $x) then . else .seen += [$x] | .todo += ($g[$x | tostring] // []) end) | .seen;
  def cycles($cards): graph($cards) as $g | ($g | keys | map({key: ., value: reach($g; tonumber)}) | from_entries) as $r
    | [$r | to_entries[] | (.key | tonumber) as $n | select(.value | any(. == $n))
       | [.value[] | select(. as $m | $r[$m | tostring] // [] | any(. == $n))] | sort] | unique;'
# YES (names(), above) is how the reason of a card blocked for the owner's yes to a visible change begins; the
# reviewer's sentence follows it.
