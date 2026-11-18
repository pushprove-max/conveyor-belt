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
# fixture <case> <origin>: a project alpha whose origin is <origin>, its one record, and its Foreman's folder.
fixture() {
  T=$B/$1 CASE=$1
  export HOME=$T/home XDG_CONFIG_HOME=$T/config XDG_DATA_HOME=$T/data XDG_STATE_HOME=$T/xstate
  M=$T/alpha FD=$T/foreman
  export CONVEYOR_FOREMAN_DIR=$FD CONVEYOR_MAIN=$M
  mkdir -p "$HOME" "$XDG_CONFIG_HOME/conveyor" "$FD" && git init -q "$M" && git -C "$M" remote add origin "$2" && mkdir -p "$M/.conveyor" \
    && jq -n '{plugin: {follow: "main"}}' > "$M/.conveyor/project.json" \
    && jq -n --arg m "$M" '{records: [{repo: "alpha", main: $m}]}' > "$XDG_CONFIG_HOME/conveyor/host.json" \
    || fail "the fixture was not made"
}
turn() { # <uuid> <reply> [<opening>]: the stop hook on a turn that ends with that reply
  jq -cn --arg u "$1" --arg r "$2" --arg o "${3:-what now}" '{type: "user", uuid: $u, message: {content: $o}},{type: "assistant", message: {content: [{type: "text", text: $r}]}}' > "$T/t.jsonl"
  jq -cn --arg t "$T/t.jsonl" '{session_id: "s1", transcript_path: $t, stop_hook_active: false}' | bash "$SRC/stop.sh" reply
}
# start: the Foreman's start-up text (SessionStart; no session is marked yet, so CONVEYOR_FOREMAN makes this one it).
start() { echo '{}' | bash "$SRC/foreman.sh" start 2>&1; }

# D1: in the plugin's own repository a plugin problem with no issue number is refused, with the reason and the form;
# the same line with "filed as #<n>" passes, and the note made at the refusal then names the issue (one note).
t_home() {
  fixture home "git@github.com:${OWN#https://github.com/}.git"
  out=$(turn u1 "$LINE")
  jq -e '.decision == "block" and (.reason | contains("plugin'"'"'s own repository") and contains("filed as #<n>") and contains("running cards keep the old engine code"))' <<<"$out" >/dev/null \
    || fail "a plugin problem with no issue number passed in the plugin's repository: $out"
  out=$(turn u2 "$LINE, filed as #449"); [ -z "$out" ] || fail "a plugin problem filed as an issue was refused: $out"
  [ "$(grep -c '^- ' "$FD/plugin-bugs.md")" = 1 ] && grep -qE '^- .* · card c20261118T045400-alpha-7 · running cards keep .*, filed as #449 · evidence: ~/cards/c20261118T045400-alpha-7\.err$' "$FD/plugin-bugs.md" \
    || fail "the note does not name the issue it was filed as, once: $(cat "$FD/plugin-bugs.md")"
  # D3: the start-up text names a noted entry with no issue, and leaves out the one that names its issue.
  printf -- '- 2026-11-18T09:54:00Z · card - · setup never sets linkFromMain · evidence: -\n' >> "$FD/plugin-bugs.md"
  out=$(start)
  grep -q 'filed as #<n>' <<<"$out" || fail "the role text does not say to file a plugin problem and name its issue: $out"
  grep -q '^- .*setup never sets linkFromMain' <<<"$out" || fail "the start-up text does not list the unfiled entry: $out"
  ! grep -q 'running cards keep' <<<"$out" || fail "the start-up text lists an entry filed as #449: $out"
}

# Older notes (made in other words, before the form) filed from the start-up list. Bugs: a filed line that only
# shared a note's card and evidence path replaced that note, so a different problem erased it; and a note with no
# card or evidence, filed in the form with "card -, evidence -", stayed listed as unfiled. The start-up list gives
# each note the line that marks it filed; saying it, or the form built from the note's own fields, replaces only it.
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
  [ "$say" = 'Plugin problem (for the conveyor-belt repo): setup never sets linkFromMain, so card c20261116T101500-alpha-7 has no packages; evidence ~/cards/c20261116T101500-alpha-7/test.log., filed as #<n>' ] \
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

# D2: in another project the same line with no number passes, as before, and the owner files it: the start-up text
# lists no entry and does not tell the Foreman to file it.
t_other() {
  fixture other https://github.com/example/alpha
  out=$(turn u1 "$LINE"); [ -z "$out" ] || fail "a plugin problem with no issue number was refused in another project: $out"
  [ "$(grep -c '^- ' "$FD/plugin-bugs.md")" = 1 ] || fail "the plugin problem was not noted: $(cat "$FD/plugin-bugs.md" 2>&1)"
  out=$(start)
  grep -q 'only they can fix or file it' <<<"$out" && ! grep -q 'filed as #<n>\|running cards keep' <<<"$out" \
    || fail "in another project the start-up text does not leave the plugin problem to the owner: $out"
}

cases=(home legacy other)
SEL=${CONVEYOR_SHELL_TEST_CASE:-${cases[*]}}; SEL=${SEL//,/ }
rc=0; pids=()
for c in $SEL; do (CASE=$c; "t_$c") & pids+=($!); done
for p in "${pids[@]}"; do wait "$p" || rc=1; done
exit "$rc"
