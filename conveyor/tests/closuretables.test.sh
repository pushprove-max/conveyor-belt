#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases: the release set takes the files the run-time tables name (tools/closure.sh TABLES: the command table
# of conveyor.sh, SNAPLIBS of commands/snapshot.sh, FETCH of hooks/units.tsx), the files a computed load declares and
# the files hooks/hooks.json and .claude-plugin/plugin.json name, and fails on a missing one and an undeclared load.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# Bug (issue 776): the command-table reader dropped a script that was missing or untracked, so the set shipped a
# command whose script was not in it, and SNAPLIBS and FETCH were not read at all. In a checkout of the set, a new
# entry of each table, with its file, is in the set with no other change; an unused sibling of a library the snapshot
# loads is not (only --unreached names it); and each entry whose file is untracked or missing fails the set, naming the
# file that holds the table and the path it expects, as does a table the reader no longer finds.
t_closuretables() {
  local c=$T/$CASE/co o=$T/$CASE/out
  mkdir -p "$c"
  ( cd "$SRC/.." && bash conveyor/tools/closure.sh | tar -cf - -T - ) | tar -C "$c" -xf - || fail "cannot copy the release set"
  echo 'hello() { :; }' > "$c/conveyor/commands/hello.sh" && echo 'extra() { :; }' > "$c/conveyor/lib/extra.sh" \
    && echo 'unused() { :; }' > "$c/conveyor/lib/zzunused.sh" && echo 'echo fetch' > "$c/hooks/units-fetch2.sh" \
    && sed -i '/^cmd watch /a cmd hello hello.sh -' "$c/conveyor/conveyor.sh" \
    && sed -i "s/^SNAPLIBS='/SNAPLIBS='extra /" "$c/conveyor/commands/snapshot.sh" \
    && sed -i "s|^const FETCH = 'hooks/units-fetch.sh'|const FETCH = 'hooks/units-fetch2.sh'|" "$c/hooks/units.tsx" \
    && grep -qx 'cmd hello hello.sh -' "$c/conveyor/conveyor.sh" && grep -q "^SNAPLIBS='extra " "$c/conveyor/commands/snapshot.sh" \
    && grep -q "^const FETCH = 'hooks/units-fetch2.sh'" "$c/hooks/units.tsx" || fail "cannot make the fixture's table entries"
  git -C "$c" init -q && git -C "$c" add -A && git -C "$c" commit -qm set || fail "cannot make the checkout a repository"
  bash "$c/conveyor/tools/closure.sh" "$c" > "$o" || fail "closure.sh failed with every table entry's file in place"
  for f in conveyor/commands/hello.sh conveyor/lib/extra.sh hooks/units-fetch2.sh; do
    grep -qxF "$f" "$o" || fail "the set misses $f, which a table names"
  done
  ! grep -qxF conveyor/lib/zzunused.sh "$o" || fail "the set holds an unused sibling of the snapshot's libraries"
  [ "$(bash "$c/conveyor/tools/closure.sh" --unreached "$c")" = conveyor/lib/zzunused.sh ] \
    || fail "--unreached did not name only the unused library"
  # Each missing target in turn: untracked (the file is still on disk), then gone from the checkout.
  git -C "$c" rm -q --cached conveyor/commands/hello.sh || fail "cannot untrack the command's script"
  ! bash "$c/conveyor/tools/closure.sh" "$c" > /dev/null 2> "$o" || fail "closure.sh passed with a command's script untracked"
  grep -qxF 'closure: conveyor/conveyor.sh: cmd names hello.sh, but conveyor/commands/hello.sh is missing or untracked' "$o" \
    || fail "closure.sh did not name conveyor/conveyor.sh and the missing script: $(cat "$o")"
  git -C "$c" add conveyor/commands/hello.sh && git -C "$c" rm -q conveyor/lib/extra.sh || fail "cannot remove the library"
  ! bash "$c/conveyor/tools/closure.sh" "$c" > /dev/null 2> "$o" || fail "closure.sh passed with a SNAPLIBS library missing"
  grep -qxF 'closure: conveyor/commands/snapshot.sh: SNAPLIBS names extra, but conveyor/lib/extra.sh is missing or untracked' "$o" \
    || fail "closure.sh did not name snapshot.sh and the missing library: $(cat "$o")"
  echo 'extra() { :; }' > "$c/conveyor/lib/extra.sh" && git -C "$c" add conveyor/lib/extra.sh && git -C "$c" rm -q hooks/units-fetch2.sh \
    || fail "cannot remove the fetch"
  ! bash "$c/conveyor/tools/closure.sh" "$c" > /dev/null 2> "$o" || fail "closure.sh passed with the FETCH file missing"
  grep -qxF 'closure: hooks/units.tsx: FETCH names hooks/units-fetch2.sh, but hooks/units-fetch2.sh is missing or untracked' "$o" \
    || fail "closure.sh did not name units.tsx and the missing fetch: $(cat "$o")"
  # A table the reader no longer finds (renamed) fails too, not read as one with no entries.
  echo 'echo fetch' > "$c/hooks/units-fetch2.sh" && git -C "$c" add hooks/units-fetch2.sh \
    && sed -i 's/^SNAPLIBS=/LIBS=/' "$c/conveyor/commands/snapshot.sh" && git -C "$c" add conveyor/commands/snapshot.sh || fail "cannot rename SNAPLIBS"
  ! bash "$c/conveyor/tools/closure.sh" "$c" > /dev/null 2> "$o" || fail "closure.sh passed with no SNAPLIBS table"
  grep -qxF 'closure: conveyor/commands/snapshot.sh: its SNAPLIBS table names no file' "$o" \
    || fail "closure.sh did not name snapshot.sh and its missing table: $(cat "$o")"
}

# A checkout of the release set, a git repository, in $T/$CASE/co.
relset() {
  c=$T/$CASE/co o=$T/$CASE/out
  mkdir -p "$c" && ( cd "$SRC/.." && bash conveyor/tools/closure.sh | tar -cf - -T - ) | tar -C "$c" -xf - \
    && git -C "$c" init -q && git -C "$c" add -A && git -C "$c" commit -qm set || fail "cannot make a checkout of the release set"
}
# closure.sh on the checkout fails, and its message is the one given.
closurefails() { # <message> <why the set would ship wrong>
  ! bash "$c/conveyor/tools/closure.sh" "$c" > /dev/null 2> "$o" || fail "closure.sh passed: $2"
  grep -qxF "$1" "$o" || fail "closure.sh did not say '$1' ($2): $(cat "$o")"
}

# Bug (issue 777): a source or run of a path a variable completes, with no table, was not followed and not reported,
# so the set shipped without the file it loads. Such a load in a file of the set fails, naming that file; with its
# declaration (the variable's assignment marked `# closure: load`) the file it names is in the set, a missing one
# fails, and so does a declaration no load reads, which would keep a stale file in the set. A declaration of two
# words fails: the load opens 'lib/part1 part2.sh' as one path, so neither part1.sh nor part2.sh is what it loads.
t_closureloads() {
  local c o
  relset
  echo 'PART=$1; . "$(dirname "$0")/lib/$PART.sh"' >> "$c/conveyor/report.sh" && git -C "$c" add -A || fail "cannot add the load"
  closurefails 'closure: conveyor/report.sh: the computed load conveyor/lib/$PART.sh has no table and no declaration' \
    "a computed load with no table and no declaration"
  sed -i 's/^PART=$1; /PART=\x27part1 part2\x27 # closure: load\n/' "$c/conveyor/report.sh" && echo 'p() { :; }' > "$c/conveyor/lib/part1.sh" \
    && echo 'p() { :; }' > "$c/conveyor/lib/part2.sh" && git -C "$c" add -A || fail "cannot add the declaration"
  closurefails 'closure: conveyor/report.sh: the declaration of PART must hold one name, as the load reads it as one path' \
    "a declaration of two names, which the load opens as one path"
  sed -i 's/^PART=.part1 part2. /PART=part1 /' "$c/conveyor/report.sh" && git -C "$c" add -A || fail "cannot make the declaration one name"
  bash "$c/conveyor/tools/closure.sh" "$c" > "$o" || fail "closure.sh failed with a declared load's file in place: $(cat "$o")"
  grep -qxF conveyor/lib/part1.sh "$o" || fail "the set misses the file the declaration names"
  git -C "$c" rm -qf conveyor/lib/part1.sh || fail "cannot remove the declared file"
  closurefails 'closure: conveyor/report.sh: the declaration of PART names part1, but conveyor/lib/part1.sh is missing or untracked' \
    "the file the declaration names is missing"
  echo 'p() { :; }' > "$c/conveyor/lib/part1.sh" && echo 'OLD=gone # closure: load' >> "$c/conveyor/report.sh" && git -C "$c" add -A \
    || fail "cannot add an unread declaration"
  closurefails 'closure: conveyor/report.sh: no computed load reads the declaration of OLD' "a declaration no load reads"
}

# Bug (issue 777): the walk did not read hooks/hooks.json's commands and modules or .claude-plugin/plugin.json's file
# fields, so a hook, a pane module or the types file Claude Code loads from the install could be missing from it. Each
# is in the set, a missing one fails naming the file that names it, and a hook only the host project runs (its
# .claude/settings.json) and a product file beside the shipped ones stay out.
t_closureplugin() {
  local c o
  relset
  for f in hooks/index.tsx hooks/sources.ts types/index.d.ts; do [ -f "$c/$f" ] || fail "the release set misses $f"; done
  mkdir -p "$c/src" && echo 'exit 0' > "$c/.claude/hooks/host-only.sh" && echo 'export {}' > "$c/hooks/product.ts" \
    && echo 'export {}' > "$c/src/app.ts" && echo 'exit 0' > "$c/.claude/hooks/new-hook.sh" && echo 'export {}' > "$c/types/next.d.ts" \
    && jq -n '{hooks: {PreToolUse: [{hooks: [{type: "command", command: "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/host-only.sh"}]}]}}' > "$c/.claude/settings.json" \
    && jq '.hooks.Stop += [{hooks: [{type: "command", command: "CONVEYOR_HOOK=1 \"${CLAUDE_PLUGIN_ROOT}\"/shim.sh .claude/hooks/new-hook.sh"}]}]' \
      "$c/hooks/hooks.json" > "$o" && mv "$o" "$c/hooks/hooks.json" \
    && jq '.types = "./types/next.d.ts"' "$c/.claude-plugin/plugin.json" > "$o" && mv "$o" "$c/.claude-plugin/plugin.json" \
    && git -C "$c" add -A || fail "cannot make the fixture"
  bash "$c/conveyor/tools/closure.sh" "$c" > "$o" || fail "closure.sh failed with every plugin file in place: $(cat "$o")"
  for f in .claude/hooks/new-hook.sh types/next.d.ts; do grep -qxF "$f" "$o" || fail "the set misses $f, which a plugin file names"; done
  for f in .claude/hooks/host-only.sh hooks/product.ts src/app.ts; do ! grep -qxF "$f" "$o" || fail "the set holds $f, which no shipped file names"; done
  [ -z "$(bash "$c/conveyor/tools/closure.sh" --unreached "$c")" ] || fail "--unreached named a file in a checkout of the set"
  git -C "$c" rm -q --cached .claude/hooks/new-hook.sh || fail "cannot untrack the new hook"
  closurefails 'closure: hooks/hooks.json: names .claude/hooks/new-hook.sh, but .claude/hooks/new-hook.sh is missing or untracked' \
    "a hook hooks.json runs is untracked"
  git -C "$c" add -A && git -C "$c" rm -qf types/next.d.ts || fail "cannot remove the types file"
  closurefails 'closure: .claude-plugin/plugin.json: names ./types/next.d.ts, but types/next.d.ts is missing or untracked' \
    "the types file plugin.json names is missing"
}
