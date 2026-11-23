#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# cause.sh: the Foreman's check that a fix issue it files has a `## Cause` section (no_cause), sourced by foreman.sh,
# whose filing hook calls it; it uses foreman.sh files and lib.sh stdin_file. It is a file of its own so that a change
# to it selects its tests (conveyor/foreman/filing-cause.test.sh, linked in .conveyor/test-links.json) and only them:
# in foreman.sh, they were one of more linked test files than a card's Test step runs.
# no_cause <hook input>: 0 when its command files a fix issue with no `## Cause` section: the command files an issue
# (foreman.sh files, or `ask <project> testissue`), and the text it carries (a body file it names, when readable, too, and
# for `--body-file -` the file a `< file` redirect names) has a `## What happens now` section or a `bug` label (`--label bug`, `-l foo,bug`, `--label=bug`); `testissue` always
# files with the pack's type label (`bug` in this pack), so it counts as a fix issue too. The section is read as
# written in the command, as files is: its text is not judged, and a body made by an expansion is not seen.
# shellcheck disable=SC2034 # NO_CAUSE is read in foreman.sh filing
NO_CAUSE='Not run: a fix issue needs a "## Cause" section, and this one has none. Name the source of the problem, not only what the reader sees. The section holds three things. First, where the bad data or behaviour comes from and why it is there at all. Second, a place in the code that already solves the same problem, or that none was found. Third, what the reader sees when the data is stale or missing. Add the section and file it again.'
no_cause() {
  local cmd f t ti=0
  cmd=$(jq -r '.tool_input.command // ""' <<<"$1" 2>/dev/null) || return 1
  t=${cmd//[\"\']/}
  [[ $t =~ (^|[[:space:];\&|])ask[[:space:]]+[^[:space:]]+[[:space:]]+testissue([[:space:]]|$) ]] && ti=1
  files "$1" || [ "$ti" = 1 ] || return 1
  if [[ $cmd =~ (--body-file|-F)[[:space:]=]+[\"\']?([^[:space:]\"\']+) ]] && f=${BASH_REMATCH[2]}; then
    # `--body-file -` reads the body from stdin: a `< file` redirect names that file (stdin_file in lib.sh).
    [ "$f" != - ] || f=$(stdin_file "$cmd") || f=-
    [ ! -f "$f" ] || cmd+=$'\n'$(cat "$f" 2>/dev/null)
  fi
  # A heading is its line whole, exactly two hashes, at a line start (up to three spaces before them, as Markdown
  # allows): after a newline (or a written \n) or the quote that opens the body, so '### Cause' and a mention of
  # '## What happens now' in a sentence are no heading.
  local hs=$'(^|\n|\\\\n|[\"\'])[ ]{0,3}##[[:space:]]+' he=$'[ \t]*(\n|\\\\n|$)'
  [[ $cmd =~ ${hs}Cause${he} ]] && return 1
  [[ $cmd =~ ${hs}What\ happens\ now${he} || $ti = 1 ]] && return 0
  grep -qiE "(^|[[:space:]])(--label|-l)(=|[[:space:]]+)?[\"']?([^[:space:]\"']*,)?bug([,\"'[:space:]]|\$)" <<<"$cmd"
}
