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
start() { echo '{}' | bash "$SRC/foreman.sh" start 2>&1; }

# D1: in the plugin's own repository a plugin problem with no issue number is refused, with the reason and the form;
# the same line with "filed as #<n>" passes, and the note made at the refusal then names the issue (one note).
t_home() {
  fixture home "git@github.com:${OWN#https://github.com/}.git"
  out=$(turn u1 "$LINE"$'\nShould I retry #7?')
  jq -e '.decision == "block" and (.reason | contains("plugin'"'"'s own repository") and contains("filed as #<n>") and contains("running cards keep the old engine code"))' <<<"$out" >/dev/null \
    || fail "a plugin problem with no issue number passed in the plugin's repository: $out"
  # Bug (#478): the refusal marked turn u1 in reply-mark, so the same unfiled line passed at the turn's next stop.
  out=$(again "$LINE"); jq -e '.decision == "block"' <<<"$out" >/dev/null \
    || fail "a plugin problem with no issue number passed at the turn's second stop: $out"
  # Bug (#478 E1, E2): with no tool call between, the refused replies were read as part of the turn's reply, so the
  # corrected one was refused for their unfiled line and their question.
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

# The default list is every t_ function in this file: a hand-kept list left t_split out (bug #558).
cases=$(declare -F | sed -n 's/^declare -f t_//p')
SEL=${CONVEYOR_SHELL_TEST_CASE:-$cases}; SEL=${SEL//,/ }
rc=0; pids=()
for c in $SEL; do (CASE=$c; "t_$c" && echo "ok [plugin-problem-$c]") & pids+=($!); done
for p in "${pids[@]}"; do wait "$p" || rc=1; done
exit "$rc"
