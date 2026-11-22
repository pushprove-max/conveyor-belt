#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 60
# A Foreman's "Plugin problem" line (stop.sh reply) and its start-up text (foreman.sh context), in the plugin's own
# repository and in any other project.
# Bug (#450): in the plugin's own repository a plugin problem was only noted in plugin-bugs.md; the Foreman never
# filed it, never saw the note again, and an entry stayed unfiled for hours until the owner asked.
set -uo pipefail
SRC=$(cd "$(dirname "$0")" && pwd -P)
B=$(mktemp -d) || exit 1
trap 'rm -rf "$B"' EXIT
cd "$B" || exit 1
unset CONVEYOR_FOREMAN_LAUNCH CONVEYOR_CARD CONVEYOR_LANE CONVEYOR_MACHINE_ID CLAUDE_CONFIG_DIR CLAUDE_PROJECT_DIR
export CONVEYOR_FOREMAN=1 CONVEYOR_FOREMAN_ASK='exit 3' CLAUDE_PLUGIN_OPTION_boardAutoOpen=false
# The plugin's own repository, as its plugin.json names it.
OWN=$(jq -r '.repository | if type == "object" then .url else . end' "$SRC/../../.claude-plugin/plugin.json")
LINE='Plugin problem (for the conveyor-belt repo): running cards keep the old engine code, card c20261118T045400-alpha-7, evidence ~/cards/c20261118T045400-alpha-7.err'
fail() { echo "FAIL [plugin-problem-$CASE]: $*" >&2; exit 1; }
# fixture <case> <origin> [<record>]: a project alpha whose origin is <origin>, its one record (default alpha, its
# main this checkout; else the record named <record>, its main on another host), and its Foreman's folder.
fixture() {
  T=$B/$1 CASE=$1
  export HOME=$T/home XDG_CONFIG_HOME=$T/config XDG_DATA_HOME=$T/data XDG_STATE_HOME=$T/xstate
  M=$T/alpha FD=$T/foreman
  export CONVEYOR_FOREMAN_DIR=$FD CONVEYOR_MAIN=$M
  mkdir -p "$HOME" "$XDG_CONFIG_HOME/conveyor" "$FD" && git init -q "$M" && git -C "$M" remote add origin "$2" && mkdir -p "$M/.conveyor" \
    && jq -n '{plugin: {follow: "main"}}' > "$M/.conveyor/project.json" \
    && jq -n --arg m "$M" --arg r "${3:-}" --arg far "$T/far/${3:-}" '{records: [if $r == "" then {repo: "alpha", main: $m} else {repo: $r, main: $far} end]}' >"$XDG_CONFIG_HOME/conveyor/host.json" \
    || fail "the fixture was not made"
}
turn() { # <uuid> <reply> [<opening>]: the stop hook on a turn that ends with that reply
  jq -cn --arg u "$1" --arg r "$2" --arg o "${3:-what now}" '{type: "user", uuid: $u, message: {content: $o}},{type: "assistant", message: {content: [{type: "text", text: $r}]}}' > "$T/t.jsonl"
  jq -cn --arg t "$T/t.jsonl" '{session_id: "s1", transcript_path: $t, stop_hook_active: false}' | bash "$SRC/stop.sh" reply
}
again() { # <reply>: the same turn's next stop after a refusal: Claude Code's stop feedback, then that reply, with no tool call
  jq -cn --arg r "$1" '{type: "user", isMeta: true, message: {content: "Stop hook feedback: refused"}},{type: "assistant", message: {content: [{type: "text", text: $r}]}}' >> "$T/t.jsonl"
  jq -cn --arg t "$T/t.jsonl" '{session_id: "s1", transcript_path: $t, stop_hook_active: true}' | bash "$SRC/stop.sh" reply
}
# start: the Foreman's start-up text (SessionStart; no session is marked yet, so CONVEYOR_FOREMAN makes this one it).
start() { echo '{}' | bash "$SRC/foreman.sh" start 2>&1 | jq -r '.hookSpecificOutput.additionalContext // empty'; }

# D1: in the plugin's own repository a plugin problem with no issue number is refused, with the reason and the form;
# the same line with "filed as #<n>" passes, and the note made at the refusal then names the issue (one note).
t_home() {
  fixture home "git@github.com:${OWN#https://github.com/}.git"
  out=$(turn u1 "$LINE"$'\nI still need to file #7.')
  jq -e '.decision == "block" and (.reason | contains("plugin'"'"'s own repository") and contains("filed as #<n>") and contains("running cards keep the old engine code"))' <<<"$out" >/dev/null \
    || fail "a plugin problem with no issue number passed in the plugin's repository: $out"
  # Bug (#478): the refusal marked turn u1 in reply-mark, so the same unfiled line passed at the turn's next stop.
  out=$(again "$LINE"); jq -e '.decision == "block"' <<<"$out" >/dev/null \
    || fail "a plugin problem with no issue number passed at the turn's second stop: $out"
  # Bug (#478 E1, E2): with no tool call between, the refused replies were read as part of the turn's reply, so the
  # corrected one was refused for their unfiled line and their unfinished-work line.
  out=$(again "$LINE, filed as #449"); [ -z "$out" ] || fail "a plugin problem filed as an issue was refused: $out"
  # Bug (#478 E2): a later stop noted a refused reply's unfiled line again, so the filed problem was listed at start-up.
  out=$(again 'Filed #449.'); [ -z "$out" ] || fail "a reply after the filed one was refused for a refused reply's line: $out"
  [ "$(grep -c '^- ' "$FD/plugin-bugs.md")" = 1 ] && grep -qE '^- .* · card c20261118T045400-alpha-7 · running cards keep .*, filed as #449 · evidence: ~/cards/c20261118T045400-alpha-7\.err$' "$FD/plugin-bugs.md" \
    || fail "the note does not name the issue it was filed as, once: $(cat "$FD/plugin-bugs.md")"
  # D3: the start-up text names a noted entry with no issue, and leaves out the one that names its issue.
  # (E2, #479) A saved note "filed as #0" (written by hand, or by a stop hook before #479) names no issue, so it is
  # listed as unfiled: the start-up filter took any number and hid it.
  printf -- '- 2026-11-18T09:54:00Z · card - · setup never sets linkFromMain · evidence: -\n- 2026-11-18T10:10:00Z · card - · npm ci runs twice, filed as #0 · evidence: -\n' >> "$FD/plugin-bugs.md"
  out=$(start)
  grep -q 'filed as #<n>' <<<"$out" || fail "the role text does not say to file a plugin problem and name its issue: $out"
  grep -q '^- .*setup never sets linkFromMain' <<<"$out" || fail "the start-up text does not list the unfiled entry: $out"
  # Bug (#482): a note with no number may name a problem the owner already filed (as #449 was), yet the start-up
  # text said "file each one now", so the Foreman filed a duplicate; it must look for an existing issue first.
  w=$(grep '^# WARNING: plugin problems noted' <<<"$out")
  grep -q 'search this repository.s issues, open and closed, for one that already reports it' <<<"$w" && grep -q 'file it now only when none does' <<<"$w" && ! grep -q 'file each one now' <<<"$w" \
    || fail "the start-up text tells the Foreman to file an unnumbered note without looking for an issue that reports it: $w"
  grep -q '^- .*npm ci runs twice, filed as #0 · evidence: ' <<<"$out" || fail "the start-up text hides a saved note filed as #0: $out"
  ! grep -q 'running cards keep' <<<"$out" || fail "the start-up text lists an entry filed as #449: $out"
}

# Bug (#564): stop.sh exits at once when reply-mark already names the turn, so the plugin check must come before
# that exit; below it, an unfiled line said after an unfinished-work refusal marked the turn passed unfiled.
t_mark() {
  fixture mark "git@github.com:${OWN#https://github.com/}.git"
  out=$(turn u1 'I still need to file #7.')
  jq -e '.decision == "block" and (.reason | contains("Unfinished work"))' <<<"$out" >/dev/null && [ "$(cat "$FD/reply-mark")" = u1 ] \
    || fail "the unfinished-work refusal did not mark turn u1 in reply-mark (reply: I still need to file #7.): $out"
  out=$(again "$LINE")
  jq -e '.decision == "block" and (.reason | contains("filed as #<n>"))' <<<"$out" >/dev/null \
    || fail "a plugin problem with no issue number passed after an unfinished-work refusal marked the turn (reply: $LINE): $out"
}

# Bug (#479): "filed as #0" names no issue, yet the stop hook passed it as filed and the start-up list hid its note,
# so a problem never filed was lost. Now the line is refused and its note stays in the unfiled list. And (E1) the note
# kept "#0" in its text, so the line said again with a valid number added a second note and left the #0 one listed.
t_zero() {
  fixture zero "git@github.com:${OWN#https://github.com/}.git"
  out=$(turn u1 "$LINE, filed as #0")
  jq -e '.decision == "block" and (.reason | contains("Not filed: running cards keep"))' <<<"$out" >/dev/null \
    || fail "a plugin problem filed as #0 passed as filed: $out"
  out=$(start); grep -q '^- .*running cards keep .*evidence: ' <<<"$out" || fail "the start-up text hides a note filed as #0: $out"
  out=$(turn u2 "$LINE, filed as #449"); [ -z "$out" ] || fail "the line with a valid issue number was refused: $out"
  [ "$(grep -c '^- ' "$FD/plugin-bugs.md")" = 1 ] && grep -q 'running cards keep .*, filed as #449 · evidence: ' "$FD/plugin-bugs.md" \
    || fail "the valid number did not take the place of the #0 note: $(cat "$FD/plugin-bugs.md")"
  out=$(start); ! grep -q 'running cards keep' <<<"$out" || fail "the start-up text lists the note filed as #449 as unfiled: $out"
}

# Bug (R28): a line ending ",filed as #449" (no space) passed the stop hook, but the start-up list did not know its
# note as filed and listed it as unfiled again.
t_nospace() {
  fixture nospace "git@github.com:${OWN#https://github.com/}.git"
  out=$(turn u1 "$LINE,filed as #449"); [ -z "$out" ] || fail "the line ending ',filed as #449' was refused: $out"
  grep -q 'running cards keep .*,filed as #449 · evidence: ' "$FD/plugin-bugs.md" || fail "the note does not end ',filed as #449': $(cat "$FD/plugin-bugs.md")"
  out=$(start); ! grep -q 'running cards keep' <<<"$out" || fail "the start-up text lists the note ending ',filed as #449' as unfiled: $out"
}

# Older notes (made in other words, before the form) filed from the start-up list. Bugs: a filed line that only
# shared a note's card and evidence path replaced that note, so a different problem erased it; and a note with no
# card or evidence, filed in the form with "card -, evidence -", stayed listed as unfiled. The start-up list gives
# each note the line that marks it filed, in the form with the note's card and evidence fields (bug #481: they were
# left out, so the line did not say the card and evidence the form asks for); saying it, or the form built from the note's own fields, replaces only it.
# A wake refusal there gives the filed form.
t_legacy() {
  local L1='- 2026-11-18T09:54:00Z · card c20261116T101500-alpha-7 · setup never sets linkFromMain, so card c20261116T101500-alpha-7 has no packages; evidence ~/cards/c20261116T101500-alpha-7/test.log. · evidence: ~/cards/c20261116T101500-alpha-7/test.log'
  fixture legacy "git@github.com:${OWN#https://github.com/}.git"
  printf -- '%s\n- 2026-11-18T10:10:00Z · card - · npm ci runs twice · evidence: -\n' "$L1" > "$FD/plugin-bugs.md"
  out=$(turn u1 'Plugin problem (for the conveyor-belt repo): the test log omits the exit status, card c20261116T101500-alpha-7, evidence ~/cards/c20261116T101500-alpha-7/test.log, filed as #450')
  [ -z "$out" ] || fail "a filed plugin problem was refused: $out"
  grep -qxF -- "$L1" "$FD/plugin-bugs.md" && [ "$(grep -c '^- ' "$FD/plugin-bugs.md")" = 3 ] \
    || fail "a different problem with the same card and evidence replaced an older note: $(cat "$FD/plugin-bugs.md")"
  say=$(start | grep -A1 -xF -- "$L1" | sed -n '2s/^ *//p')
  [ "$say" = 'Plugin problem (for the conveyor-belt repo): setup never sets linkFromMain, so card c20261116T101500-alpha-7 has no packages; evidence ~/cards/c20261116T101500-alpha-7/test.log., card c20261116T101500-alpha-7, evidence ~/cards/c20261116T101500-alpha-7/test.log, filed as #<n>' ] \
    || fail "the start-up text does not give the line that marks the older note filed: $say"
  out=$(turn u2 "${say%<n>}449"$'\nPlugin problem (for the conveyor-belt repo): npm ci runs twice, card -, evidence -, filed as #451')
  [ -z "$out" ] || fail "a filed plugin problem was refused: $out"
  [ "$(grep -c '^- ' "$FD/plugin-bugs.md")" = 3 ] && grep -q '^- 2026-11-18T09:54:00Z · card c20261116T101500-alpha-7 · setup .*, filed as #449 · evidence: ' "$FD/plugin-bugs.md" \
    && grep -qxF -- '- 2026-11-18T10:10:00Z · card - · npm ci runs twice, card -, evidence -, filed as #451 · evidence: -' "$FD/plugin-bugs.md" \
    || fail "a filed line did not take its older note's place: $(cat "$FD/plugin-bugs.md")"
  out=$(start); ! grep -q 'WARNING: plugin problems' <<<"$out" || fail "the start-up text lists a filed note as unfiled: $out"
  echo 'Conveyor: alpha: blocked: #7' > "$FD/last-wake.txt"
  out=$(turn u2 '#12 landed.' 'Stop hook feedback: Conveyor: alpha: blocked: #7')
  jq -e '.decision == "block" and (.reason | contains("evidence <path>, filed as #<n>'"'"'")) and (.reason | contains("alone") | not)' <<<"$out" >/dev/null \
    || fail "the wake refusal does not give the filed form in the plugin's repository: $out"
}

# Split host: the Foreman runs in a checkout on the owner's machine and its record, named for the checkout's
# repository, has its main on the belt's host. Bug (#480): plugin_home looked only at that main, not on this
# machine, so the plugin's own repository passed a plugin problem with no issue number.
t_split() {
  fixture split "git@github.com:${OWN#https://github.com/}.git" "${OWN##*/}"
  out=$(turn u1 "$LINE")
  jq -e '.decision == "block" and (.reason | contains("filed as #<n>"))' <<<"$out" >/dev/null \
    || fail "a plugin problem with no issue number passed in the plugin's repository with its belt on another host: $out"
  out=$(start)
  grep -q 'filed as #<n>' <<<"$out" && grep -q '^- .*running cards keep' <<<"$out" \
    || fail "with its belt on another host the start-up text does not say to file the plugin problem and list it: $out"
  # The note saved from a line in the form is listed with the line that files it: that line, not its card and
  # evidence said twice (bug #481 E1: the start-up list appended them again).
  say=$(grep -A1 '^- .*running cards keep' <<<"$out" | sed -n '2s/^ *//p')
  [ "$say" = "$LINE, filed as #<n>" ] || fail "the start-up text does not give the noted line to file: $say"
  out=$(turn u2 "${say%<n>}449"); [ -z "$out" ] || fail "the line the start-up text gives to file was refused: $out"
}

# D2: in another project the same line with no number passes, as before, and the owner files it: the start-up text
# lists no entry and does not tell the Foreman to file it.
t_other() {
  fixture other https://github.com/example/alpha
  out=$(turn u1 "$LINE"); [ -z "$out" ] || fail "a plugin problem with no issue number was refused in another project: $out"
  [ "$(grep -c '^- ' "$FD/plugin-bugs.md")" = 1 ] || fail "the plugin problem was not noted: $(cat "$FD/plugin-bugs.md" 2>&1)"
  out=$(start)
  grep -q 'only they can fix or file it' <<<"$out" && ! grep -q 'filed as #<n>\|running cards keep' <<<"$out" \
    || fail "in another project the start-up text does not leave the plugin problem to the owner: $out"
  # Bug (#483): here the owner files it, so the Foreman reporting the issue they filed replaced the first note; it
  # must add its own row, as before #450.
  out=$(turn u2 "$LINE, filed as #449"); [ -z "$out" ] || fail "a filed plugin problem was refused in another project: $out"
  [ "$(grep -c '^- ' "$FD/plugin-bugs.md")" = 2 ] && grep -q ' · running cards keep .*alpha-7\.err · evidence: ' "$FD/plugin-bugs.md" \
    || fail "in another project a filed line replaced the older note: $(cat "$FD/plugin-bugs.md")"
}

# Bug (#1350): a line with no card id got its first issue number as its note's card, so the Board's report hid that
# number as <card> and showed the other. Only a card id goes in the card field; the text keeps both numbers.
t_issuecard() {
  fixture issuecard https://github.com/example/alpha
  reply='Plugin problem (for the conveyor-belt repo): the fix seems to still cover them, see #12 and #13, evidence ~/cards/x.log'
  out=$(turn u1 "$reply")
  [ -z "$out" ] || fail "the reply '$reply' was refused: $out"
  grep -qE '^- [^ ]+ · card - · the fix seems to still cover them, see #12 and #13, evidence ~/cards/x\.log · evidence: ' "$FD/plugin-bugs.md" \
    || fail "for the reply '$reply' the note's card field is not - or its text lost an issue number: $(cat "$FD/plugin-bugs.md" 2>&1)"
}

# Bug (#1357): the refusal of a [likely] line was fooled by deleting the tag, which left an unmarked guess in the
# report. A line may carry "cause not checked: <text>" before its card and evidence: it passes and is noted whole, with
# its card and evidence fields read from the rest of the line (not from the cause).
t_cause() {
  fixture cause https://github.com/example/alpha
  line='Plugin problem (for the conveyor-belt repo): control release 1345 leaves card 1345 held, it should start, cause not checked: the open range, see ~/other/x.log, still covers it, card c20261118T045400-alpha-7, evidence ~/cards/x.log'
  out=$(turn u1 "$line"); [ -z "$out" ] || fail "the plugin problem '$line' with a cause not checked part was refused: $out"
  grep -qE '^- [^ ]+ · card c20261118T045400-alpha-7 · control release 1345 leaves card 1345 held, it should start, cause not checked: the open range, see ~/other/x\.log, still covers it, card c20261118T045400-alpha-7, evidence ~/cards/x\.log · evidence: ~/cards/x\.log$' "$FD/plugin-bugs.md" \
    || fail "the plugin problem '$line' was not noted with its cause part, card and evidence: $(cat "$FD/plugin-bugs.md" 2>&1)"
}

# Bug (#1357): a line with [likely] and no cause part was refused. It passes, and its note has the tagged text in a
# "cause not checked:" part before the card, with no [likely] left in the note.
t_guess() {
  fixture guess https://github.com/example/alpha
  line='Plugin problem (for the conveyor-belt repo): control release 1345 leaves card 1345 held in foreman status, it should be started, card c20261118T045400-alpha-7, evidence ~/cards/x.log; the open range seems to still cover it [likely]'
  out=$(turn u1 "$line"); [ -z "$out" ] || fail "the plugin problem '$line' with [likely] was refused: $out"
  grep -qE '^- [^ ]+ · card c20261118T045400-alpha-7 · control release 1345 leaves card 1345 held in foreman status, it should be started, cause not checked: the open range seems to still cover it, card c20261118T045400-alpha-7, evidence ~/cards/x\.log · evidence: ~/cards/x\.log$' "$FD/plugin-bugs.md" \
    || fail "the plugin problem '$line' was not noted with its tagged text in a cause not checked part: $(cat "$FD/plugin-bugs.md" 2>&1)"
  out=$(turn u2 "$line"); [ -z "$out" ] || fail "the same plugin problem '$line' said again was refused: $out"
  [ "$(grep -c '^- ' "$FD/plugin-bugs.md")" = 1 ] || fail "the same plugin problem '$line' said again was noted twice: $(cat "$FD/plugin-bugs.md")"
}

# Bug (review of #1357): a cause with the words ", card lookups use old data" was cut there, as if they began the card
# field, and the rest of the guess went to the report as fact. Only a card id or an evidence path ends the cause.
t_causewords() {
  fixture causewords https://github.com/example/alpha
  line='Plugin problem (for the conveyor-belt repo): setup fails, it should pass, cause not checked: the cache is stale, card lookups use old data, evidence the log, card c20261118T045400-alpha-7, evidence ~/cards/x.log'
  out=$(turn u1 "$line"); [ -z "$out" ] || fail "the plugin problem '$line' was refused: $out"
  grep -qE '^- [^ ]+ · card c20261118T045400-alpha-7 · setup fails, it should pass, cause not checked: the cache is stale, card lookups use old data, evidence the log, card c20261118T045400-alpha-7, evidence ~/cards/x\.log · evidence: ~/cards/x\.log$' "$FD/plugin-bugs.md" \
    || fail "the plugin problem '$line' did not keep the words of its cause in the cause part: $(cat "$FD/plugin-bugs.md" 2>&1)"
  line='Plugin problem (for the conveyor-belt repo): setup fails, it should pass, card lookups use old data [likely], card c20261118T045400-alpha-8, evidence ~/cards/y.log'
  out=$(turn u2 "$line"); [ -z "$out" ] || fail "the plugin problem '$line' was refused: $out"
  grep -qE ' · setup fails, it should pass, cause not checked: card lookups use old data, card c20261118T045400-alpha-8, evidence ~/cards/y\.log · evidence: ~/cards/y\.log$' "$FD/plugin-bugs.md" \
    || fail "the plugin problem '$line': a tagged clause that starts with 'card' was not moved to the cause part: $(cat "$FD/plugin-bugs.md" 2>&1)"
}

# Bug (#1405): a guess with a comma before its [likely] tag kept its first part as fact: only the clause holding the
# tag moved, so 'the cache, maybe, is stale [likely]' gave 'the cache, maybe, cause not checked: is stale'. A tagged
# clause with no subject, or a one-word aside, goes on the clause before it, so the whole guess moves.
t_guesscomma() {
  CASE=guesscomma
  eval "$(sed -n '/^plug_cause() {/,/^}/p; /^plug_join() /p; /^plug_untag() /p' "$SRC/stop.sh")"
  local in='the cache, maybe, is stale [likely], card c20260101T000000-x'
  plug_cause "$in"
  [ "$BODY" = 'cause not checked: the cache, maybe, is stale, card c20260101T000000-x' ] \
    || fail "plug_cause '$in' did not move the whole guess into the cause part: BODY '$BODY'"
  # Bug (#1405 review): a one-word guess that is no hedge word took the clause before it, the expected result, too.
  in='setup fails, it should pass, timeout [likely], card -, evidence -'
  plug_cause "$in"
  [ "$BODY" = 'setup fails, it should pass, cause not checked: timeout, card -, evidence -' ] \
    || fail "plug_cause '$in' moved a clause that is not part of the one-word guess into the cause part: BODY '$BODY'"
}

# Bug (review of #1357): a [likely] tag at the end of the line, after the evidence, put the evidence path in the cause
# part and left the claim outside it. The tag marks the text before the card and evidence fields, so that goes into it.
t_guessend() {
  fixture guessend https://github.com/example/alpha
  out=$(turn u1 "$LINE [likely]"); [ -z "$out" ] || fail "the plugin problem '$LINE [likely]' was refused: $out"
  grep -qE '^- [^ ]+ · card c20261118T045400-alpha-7 · cause not checked: running cards keep the old engine code, card c20261118T045400-alpha-7, evidence ~/cards/c20261118T045400-alpha-7\.err · evidence: ~/cards/c20261118T045400-alpha-7\.err$' "$FD/plugin-bugs.md" \
    || fail "the plugin problem '$LINE [likely]' was not noted with its claim in the cause part: $(cat "$FD/plugin-bugs.md" 2>&1)"
}

# Bug (review of #1357): with empty fields ("card -, evidence -") a [likely] tag at the end took "evidence -" for the
# claim: the note had "cause not checked: evidence -" and the claim stayed outside it. "-" is a field's empty value.
t_guessempty() {
  fixture guessempty https://github.com/example/alpha
  line='Plugin problem (for the conveyor-belt repo): running cards keep the old engine code, card -, evidence - [likely]'
  out=$(turn u1 "$line"); [ -z "$out" ] || fail "the plugin problem '$line' was refused: $out"
  grep -qE '^- [^ ]+ · card - · cause not checked: running cards keep the old engine code, card -, evidence - · evidence: -$' "$FD/plugin-bugs.md" \
    || fail "the plugin problem '$line' was not noted with its claim in the cause part: $(cat "$FD/plugin-bugs.md" 2>&1)"
  line='Plugin problem (for the conveyor-belt repo): setup fails, it should pass, cause not checked: the cache is stale, card -, evidence -'
  out=$(turn u2 "$line"); [ -z "$out" ] || fail "the plugin problem '$line' was refused: $out"
  grep -qE ' · setup fails, it should pass, cause not checked: the cache is stale, card -, evidence - · evidence: -$' "$FD/plugin-bugs.md" \
    || fail "the plugin problem '$line' did not keep its cause part before the empty fields: $(cat "$FD/plugin-bugs.md" 2>&1)"
}

# Bug (#1357): in the plugin's own repository a [likely] clause before "filed as #<n>" passes as a filed line and keeps
# its issue number at the end of the note, after the cause part.
t_guesshome() {
  fixture guesshome "git@github.com:${OWN#https://github.com/}.git"
  line="$LINE, filed as #449"; line=${line/, card /, the lock seems stale [likely], card }
  out=$(turn u1 "$line"); [ -z "$out" ] || fail "the filed plugin problem '$line' with [likely] was refused: $out"
  grep -qE ' · running cards keep the old engine code, cause not checked: the lock seems stale, card c20261118T045400-alpha-7, evidence ~/cards/c20261118T045400-alpha-7\.err, filed as #449 · evidence: ' "$FD/plugin-bugs.md" \
    || fail "the filed plugin problem '$line' was not noted with its cause part before the card and its issue at the end: $(cat "$FD/plugin-bugs.md" 2>&1)"
}

# Bug (#1352): the start text asked for "what you saw", so a guess fitted the form. It asks for the command, what it
# did and what was expected, in the plugin's own repository and in any other project.
form_check() {
  local own=$1
  fixture "form$own" "$([ "$own" = home ] && echo "git@github.com:${OWN#https://github.com/}.git" || echo https://github.com/example/alpha)"
  out=$(start)
  grep -qF 'Plugin problem (for the conveyor-belt repo): <the command or step>, <what it did>, <what you expected>[, cause not checked: <what you think the cause is>], card <card>, evidence <path>' <<<"$out" \
    || fail "the start text in the $own project has no form with the command, what it did and what was expected: $out"
}
t_formhome() { form_check home; }
t_formother() { form_check other; }

# The default list is every t_ function in this file: a hand-kept list left t_split out (bug #558).
cases=$(declare -F | sed -n 's/^declare -f t_//p')
SEL=${CONVEYOR_SHELL_TEST_CASE:-$cases}; SEL=${SEL//,/ }
for c in $SEL; do declare -F "t_$c" >/dev/null || { echo "unknown case $c" >&2; exit 2; }; done
rc=0; pids=()
for c in $SEL; do (CASE=$c; "t_$c" && echo "ok [plugin-problem-$c]") & pids+=($!); done
for p in "${pids[@]}"; do wait "$p" || rc=1; done
exit "$rc"
