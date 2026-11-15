#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Pins the citation gate: a memory or rule line citing ruling:<id> passes only when the decision log holds that id
# and it is not void. Without it a note can credit the owner with a ruling, or a time, that was never given.
set -u
. "$(dirname "$0")/lib/rulings-fixture.sh"
HOOK=$PLUG/.claude/hooks/ruling-cite-gate.sh
mkdir -p "$T/state" "$MAIN/.claude/rules"
printf '%s\n' '{"id":"q-20261111-120000-1-abc123","source":"ask","question":"Ship?","answer":"Yes","pick":"recommended"}' \
  '{"id":"q-20261111-120001-1-def456","source":"ask","question":"Ship?","answer":"Yes","pick":"recommended","void":true}' > "$LOG"
F=$MAIN/.claude/rules/deploys.md
write() { jq -cn --arg f "$F" --arg c "$1" '{tool_name:"Write", tool_input:{file_path:$f, content:$c}}' | bash "$HOOK" >/dev/null 2>&1; echo $?; }

check "a logged id passes" 0 "$(write 'Deploys wait for tests (ruling:q-20261111-120000-1-abc123).')"
check "an id the log does not hold is refused" 2 "$(write 'Deploys wait for tests (ruling:q-20261111-120000-1-ffffff).')"
check "a made-up id of another shape is refused" 2 "$(write 'Deploys wait (ruling:r-made-up).')"
check "a void row's id is refused" 2 "$(write 'Deploys wait (ruling:q-20261111-120001-1-def456).')"
check "one unknown id beside a logged one is refused" 2 \
  "$(write 'Deploys wait (ruling:q-20261111-120000-1-abc123, ruling:q-20261111-120000-2-abc123).')"
# An old line already on disk is not re-screened; a new line is.
printf '%s\n' 'Old rule (ruling:q-19990101-000000-1-000000).' 'Other rule.' > "$F"
check "an unchanged old line is grandfathered" 0 \
  "$(jq -cn --arg f "$F" '{tool_name:"Edit", tool_input:{file_path:$f, old_string:"Other rule", new_string:"Other rule, kept"}}' | bash "$HOOK" >/dev/null 2>&1; echo $?)"
check "an edit that adds an unknown citation is refused" 2 \
  "$(jq -cn --arg f "$F" '{tool_name:"Edit", tool_input:{file_path:$f, old_string:"Old rule", new_string:"New rule (ruling:q-20261111-130000-1-123456)"}}' | bash "$HOOK" >/dev/null 2>&1; echo $?)"
# An edit's own text need not hold `ruling:` to change a cited id: the line it leaves is screened.
printf '%s\n' 'Deploys wait (ruling:q-20261111-120000-1-abc123).' > "$F"
check "an edit that changes only an id's suffix to an unknown one is refused" 2 \
  "$(jq -cn --arg f "$F" '{tool_name:"Edit", tool_input:{file_path:$f, old_string:"abc123", new_string:"ffffff"}}' | bash "$HOOK" >/dev/null 2>&1; echo $?)"
# A path with ./ or ../ segments, or relative to the project, names the same rules file.
check "a rules path with ./ and ../ segments is screened" 2 \
  "$(jq -cn --arg f "$MAIN/.claude/./x/../rules/deploys.md" '{tool_name:"Write", tool_input:{file_path:$f, content:"ruling:unknown"}}' | bash "$HOOK" >/dev/null 2>&1; echo $?)"
check "a rules path relative to the project is screened" 2 \
  "$(jq -cn --arg c "$MAIN" '{tool_name:"Write", cwd:$c, tool_input:{file_path:".claude/./rules/deploys.md", content:"ruling:unknown"}}' | bash "$HOOK" >/dev/null 2>&1; echo $?)"
# A symlink is the file it points at: a folder or file linked into rules is screened like the rules path itself.
ln -s "$MAIN/.claude/rules" "$MAIN/rules-link"
check "a rules path through a symlinked folder is screened" 2 \
  "$(jq -cn --arg c "$MAIN" '{tool_name:"Write", cwd:$c, tool_input:{file_path:($c + "/rules-link/deploys.md"), content:"ruling:unknown"}}' | bash "$HOOK" >/dev/null 2>&1; echo $?)"
ln -s .claude/rules/deploys.md "$MAIN/deploys-link.md"
check "a symlinked file that points at a rules file is screened" 2 \
  "$(jq -cn --arg f "$MAIN/deploys-link.md" '{tool_name:"Write", tool_input:{file_path:$f, content:"ruling:unknown"}}' | bash "$HOOK" >/dev/null 2>&1; echo $?)"
# `..` after a symlink climbs from the link's target, as the write itself does: link/../x lands in rules, not beside link.
mkdir -p "$MAIN/.claude/rules/sub"; ln -s "$MAIN/.claude/rules/sub" "$MAIN/sub-link"
check "a .. after a symlink into rules is screened where it lands" 2 \
  "$(jq -cn --arg c "$MAIN" '{tool_name:"Write", cwd:$c, tool_input:{file_path:($c + "/sub-link/../deploys.md"), content:"ruling:unknown"}}' | bash "$HOOK" >/dev/null 2>&1; echo $?)"
# A newline is a legal character in a name: a link target, or a path, holding one is still followed to its end.
mkdir -p "$MAIN/x"$'\n'; ln -s "$MAIN/x"$'\n'"/../.claude/rules" "$MAIN/nl-link"
check "a symlink whose target holds a newline is screened where it lands" 2 \
  "$(jq -cn --arg c "$MAIN" '{tool_name:"Write", cwd:$c, tool_input:{file_path:($c + "/nl-link/deploys.md"), content:"ruling:unknown"}}' | bash "$HOOK" >/dev/null 2>&1; echo $?)"
ln -s "$MAIN/.claude/rules" "$MAIN/r"$'\n'; ln -s "$MAIN/r"$'\n' "$MAIN/nl-end-link"
check "a symlink whose target ends in a newline is screened where it lands" 2 \
  "$(jq -cn --arg c "$MAIN" '{tool_name:"Write", cwd:$c, tool_input:{file_path:($c + "/nl-end-link/deploys.md"), content:"ruling:unknown"}}' | bash "$HOOK" >/dev/null 2>&1; echo $?)"
check "a written path holding a newline is screened where it lands" 2 \
  "$(jq -cn --arg c "$MAIN" '{tool_name:"Write", cwd:$c, tool_input:{file_path:($c + "/x\n/../.claude/rules/deploys.md"), content:"ruling:unknown"}}' | bash "$HOOK" >/dev/null 2>&1; echo $?)"
# A link to a name ending in a newline is that name, not the one without it: the other file's lines are not grandfathered.
printf '%s\n' 'ruling:unknown' > "$MAIN/.claude/rules/new.md"; ln -s "$MAIN/.claude/rules/new.md"$'\n' "$MAIN/nl-alias"
check "a symlink to a name ending in a newline does not take another file's lines as old" 2 \
  "$(jq -cn --arg f "$MAIN/nl-alias" '{tool_name:"Write", tool_input:{file_path:$f, content:"ruling:unknown"}}' | bash "$HOOK" >/dev/null 2>&1; echo $?)"
# A MultiEdit whose edits name their own paths screens each of them.
check "a MultiEdit citing an unknown id under a per-edit rules path is refused" 2 \
  "$(jq -cn --arg f "$F" '{tool_name:"MultiEdit", tool_input:{edits:[{file_path:$f, old_string:"Deploys wait", new_string:"ruling:unknown"}]}}' | bash "$HOOK" >/dev/null 2>&1; echo $?)"
check "a MultiEdit whose rules edit names its own path beside another file is refused" 2 \
  "$(jq -cn --arg o "$MAIN/notes.txt" --arg f "$F" '{tool_name:"MultiEdit", tool_input:{file_path:$o, edits:[{new_string:"x", old_string:""}, {file_path:$f, old_string:"Deploys wait", new_string:"ruling:unknown"}]}}' | bash "$HOOK" >/dev/null 2>&1; echo $?)"
check "a file outside memory and rules is not screened" 0 \
  "$(jq -cn --arg f "$MAIN/notes.txt" '{tool_name:"Write", tool_input:{file_path:$f, content:"ruling:nothing"}}' | bash "$HOOK" >/dev/null 2>&1; echo $?)"
check "--id passes a logged id" 0 "$(bash "$HOOK" --id q-20261111-120000-1-abc123; echo $?)"
check "--id refuses an unknown id" 1 "$(bash "$HOOK" --id q-20261111-120000-1-000000; echo $?)"
finish
