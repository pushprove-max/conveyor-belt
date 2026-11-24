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
# unfenced <inline> <quote> <text>: the text without its fenced code blocks. A fence is a line of three or more backticks
# or tildes, up to three spaces before them; an opener of backticks has no backtick after them (Markdown). The block ends
# at a line of that fence character at least as often with nothing after it, or at the end of the text. With <inline> 1
# (text written in a shell quote, as `--body '...'`) a fence may also follow the quote that opens the body (and up to three
# spaces); that block also ends where its quote closes (the next quote of that kind with no backslash before it), and a
# closing fence may be followed by the closing quote, where the text goes on after it: <quote> is that quote, or empty
# for either. With <inline> 0 (a here-document or a body file, whose text is Markdown as written) a quote is no part of
# a fence.
unfenced() {
  awk -v inline="$1" -v bq="$2" -v q="'" -v dq='"' '
    function strip(x) { sub(/^[ ]?[ ]?[ ]?/, "", x); return x }
    function isq(c) { return bq == "" ? (c == q || c == dq) : c == bq }
    # fence: the line from its fence, or "" when none starts in it; fq is the quote the fence follows, or "" for none
    function fence(line,   c, i) {
      fq = ""; c = strip(line)
      if (c ~ /^[`~]/) return c
      if (inline == 1)
        for (i = 1; i < length(line); i++)
          if (isq(substr(line, i, 1)) && (i == 1 || substr(line, i - 1, 1) ~ /[ \t$]/) && strip(substr(line, i + 1)) ~ /^[`~]/) {
            fq = substr(line, i, 1); return strip(substr(line, i + 1)) }
      return "" }
    # qend: where the first quote <cq> with no backslash before it is in <s>, or 0 when none is
    function qend(s, cq,   i) {
      for (i = 1; i <= length(s); i++)
        if (substr(s, i, 1) == "\\") i++
        else if (substr(s, i, 1) == cq) return i
      return 0 }
    {
      line = $0
      while (1) {
        if (open == "") {
          c = fence(line); ch = substr(c, 1, 1); k = 0
          while (ch != "" && substr(c, k + 1, 1) == ch) k++
          if (!(k >= 3 && !(ch == "`" && index(substr(c, k + 1), "`")))) { print line; next }
          open = ch; n = k; oq = fq
          # A block after a quote can end on its own line (a title of ~~~ and a word): read on after the fence.
          if (oq == "") next
          line = substr(c, k + 1); continue }
        c = strip(line); k = 0
        while (substr(c, k + 1, 1) == open) k++
        r = substr(c, k + 1); sub(/^[ \t]*/, "", r)
        if (k >= n && r == "") { open = ""; next }
        if (k >= n && inline == 1 && isq(substr(r, 1, 1))) { open = ""; print r; next }
        # The quote that the block follows ends its text, so the block ends there too: a title whose written \n became a
        # line break ends at its closing quote, not at its line. The rest of the line is read again from that quote.
        if (oq == "" || !(j = qend(line, oq))) next
        open = ""; line = substr(line, j) } }' <<<"$3"
}
no_cause() {
  local cmd f t ti=0 fc=
  cmd=$(jq -r '.tool_input.command // ""' <<<"$1" 2>/dev/null) || return 1
  t=${cmd//[\"\']/}
  [[ $t =~ (^|[[:space:];\&|])ask[[:space:]]+[^[:space:]]+[[:space:]]+testissue([[:space:]]|$) ]] && ti=1
  files "$1" || [ "$ti" = 1 ] || return 1
  if [[ $cmd =~ (--body-file|-F)[[:space:]=]+[\"\']?([^[:space:]\"\']+) ]] && f=${BASH_REMATCH[2]}; then
    # `--body-file -` reads the body from stdin: a `< file` redirect names that file (stdin_file in lib.sh).
    [ "$f" != - ] || f=$(stdin_file "$cmd") || f=-
    [ ! -f "$f" ] || fc=$(cat "$f" 2>/dev/null)
  fi
  # A heading is its line whole, exactly two hashes, at a line start (up to three spaces before them, as Markdown
  # allows): after a newline (or a written \n) or the quote that opens the body, so '### Cause' and a mention of
  # '## What happens now' in a sentence are no heading.
  # A line inside a fenced code block (``` or ~~~) is no heading: the headings are read from the text without its fences.
  local hs=$'(^|\n|["\'])[ ]{0,3}##[[:space:]]+' he=$'[ \t]*(\n|$)' hc c=$cmd inl=1 bq='' hd=$'<<-?[ ]*[\'"]?[A-Za-z_][A-Za-z_0-9]*[\'"]?[ ]*\\)*[ ]*\n'
  # A command with a here-document (`<<WORD` ending its line) holds its body as written: `\n` there is text, and a quote
  # ends nothing; so does a body file (read apart from the command). In an inline body a written `\n` is a line break,
  # but `\\n` is a backslash and an n; the quote that opens the body is the one that closes it.
  if [[ $cmd =~ $hd ]]; then inl=0
  else
    [[ $cmd =~ (^|[[:space:]])(--body|-b)[[:space:]=]+\$?([\"\']) ]] && bq=${BASH_REMATCH[3]}
    c=${cmd//\\\\/$'\001'}; c=${c//\\n/$'\n'}; c=${c//$'\001'/\\\\}
  fi
  hc=$(unfenced "$inl" "$bq" "$c")
  [ -z "$fc" ] || hc+=$'\n'$(unfenced 0 "" "$fc")
  [[ $hc =~ ${hs}Cause${he} ]] && return 1
  [[ $hc =~ ${hs}What\ happens\ now${he} || $ti = 1 ]] && return 0
  grep -qiE "(^|[[:space:]])(--label|-l)(=|[[:space:]]+)?[\"']?([^[:space:]\"']*,)?bug([,\"'[:space:]]|\$)" <<<"$cmd"
}
