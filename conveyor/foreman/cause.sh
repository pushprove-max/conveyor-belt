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
# a fence. A fence may follow list markers (`- `, `* `, `+ `, `1. `, `1) `, nested too); its block then holds the lines
# indented at least as far as the item's text (blank lines too), and a line indented less ends it, as it ends the item.
# Its closing fence is read after that indent. A fence on a later line of the item, indented at least as far as its text,
# is in the item in the same way, and in the outer item when it is indented less than a nested one. A thematic break
# (`***`) ends the list. A tab indents to the next multiple of four columns. An ordered marker that
# does not start at 1 is no list marker on a line that goes on a paragraph (outside a list), as such a list cannot
# interrupt the paragraph.
unfenced() {
  awk -v inline="$1" -v bq="$2" -v q="'" -v dq='"' '
    function strip(x) { sub(/^[ ]?[ ]?[ ]?/, "", x); return x }
    function isq(c) { return bq == "" ? (c == q || c == dq) : c == bq }
    function tab(v, ch) { return ch == " " ? v + 1 : v + 4 - v % 4 }
    # col: the column of the first character of x that is not a space or a tab
    function col(x,   i, v) { for (i = 1; substr(x, i, 1) ~ /^[ \t]$/; i++) v = tab(v, substr(x, i, 1)); return v + 0 }
    # cut: x without w columns of its indent (a tab that goes past them leaves its rest as spaces)
    function cut(x, w,   i, v) {
      for (i = 1; v < w && substr(x, i, 1) ~ /^[ \t]$/; i++) v = tab(v, substr(x, i, 1))
      return substr("   ", 1, v - w) substr(x, i) }
    # item: x without its list markers; W is the width they take (0 when none), the indent of the item text. With
    # <para> 1 x goes on a paragraph, so a first ordered marker that does not start at 1 is none.
    # M[1..nm] is the width each marker takes with those before it (the indent of each nested item text).
    function item(x, para,   m) {
      W = nm = 0
      while (match(x, /^[ ]?[ ]?[ ]?([-*+]|[0-9]+[.)])[ ][ ]?[ ]?[ ]?/)) {
        m = substr(x, 1, RLENGTH)
        if (!W && para && m ~ /^[ ]*[0-9]/ && m !~ /^[ ]*0*1[.)]/) break
        W += RLENGTH; M[++nm] = W; x = substr(x, RLENGTH + 1) }
      return W ? x : strip(x) }
    # lazy: 1 when x (a line indented less than the item it would be in, without the indent of the items it is in) goes
    # on the paragraph of the line before: it is no fence, heading, thematic break (`***`, `---`, `___`) or list item.
    function lazy(x,   y) {
      if (!P) return 0
      x = strip(x); y = x; gsub(/[ \t]/, "", y)
      if (x ~ /^([`~]|#[#]?[#]?[#]?[#]?[#]?([ \t]|$))/ || y ~ /^(\*\*\*+|---+|___+)$/) return 0
      item(x, 0); return !W }
    # fence: the line from its fence, or "" when none starts in it; fq is the quote the fence follows, or "" for none; W is
    # the indent of the list item it is in (of the line start when none). S[1..ns] are the indents of the text of the open
    # list items, outer first: a line is in each item it is indented at least as far as, so it is read after the indent of
    # the last of them (a fence on a later line of an item is in the item too). A line indented less than an item that is
    # no paragraph text going on (after a blank line, or a fence, heading, thematic break or list item) ends that item.
    function fence(line,   c, i, k, w) {
      fq = ""; k = ns
      if (line !~ /^[ \t]*$/) {
        while (k > 0 && S[k] > col(line)) k--
        if (k < ns && !lazy(cut(line, S[k] + 0))) ns = k }
      w = k ? S[k] : 0
      c = item(w ? cut(line, w) : line, P && !L); W += w
      for (i = 1; i <= nm; i++) S[++ns] = w + M[i]
      w = W
      if (c ~ /^[`~]/) return c
      if (inline == 1)
        for (i = 1; i < length(line); i++)
          if (isq(substr(line, i, 1)) && (i == 1 || substr(line, i - 1, 1) ~ /[ \t$]/) && (c = item(substr(line, i + 1), 0)) ~ /^[`~]/) {
            fq = substr(line, i, 1); return c }
      W = w; return "" }
    # qend: where the first quote <cq> with no backslash before it is in <s>, or 0 when none is
    function qend(s, cq,   i) {
      for (i = 1; i <= length(s); i++)
        if (substr(s, i, 1) == "\\") i++
        else if (substr(s, i, 1) == cq) return i
      return 0 }
    # A line indented less than the list item of an open fence ends the item, and its block with it.
    open != "" && W > 0 && $0 !~ /^[ \t]*$/ && col($0) < W { open = "" }
    {
      line = $0
      while (1) {
        if (open == "") {
          c = fence(line); ch = substr(c, 1, 1); k = 0
          while (ch != "" && substr(c, k + 1, 1) == ch) k++
          if (!(k >= 3 && !(ch == "`" && index(substr(c, k + 1), "`")))) {
            # P: the line before goes on a paragraph; L: that paragraph is in a list.
            if ($0 ~ /^[ \t]*$/ || $0 ~ /^[ ]?[ ]?[ ]?#[#]?[#]?[#]?[#]?[#]?([ \t]|$)/) P = 0
            else if (W) P = L = 1
            else { if (!P && col($0) == 0) L = 0; P = 1 }
            # The line that opens a here-document ends the command text: the body starts a new paragraph.
            if (inline != 1 && $0 ~ /<<-?[ ]*["\047]?[A-Za-z_][A-Za-z_0-9]*["\047]?[ ]*\)*[ ]*$/) P = 0
            print line; next }
          open = ch; n = k; oq = fq; P = 0; if (W) L = 1
          # A block after a quote can end on its own line (a title of ~~~ and a word), at its closing quote: read on from
          # that quote. The rest of the opening line is its info string, never a closing fence (`~~~ ~~~` stays open).
          if (oq == "" || !(j = qend(substr(c, k + 1), oq))) next
          open = ""; line = substr(substr(c, k + 1), j); continue }
        # A closing fence is up to three columns past the item indent, tabs counted to their column.
        c = line; if (col(line) - W < 4) sub(/^[ \t]*/, "", c); k = 0
        while (substr(c, k + 1, 1) == open) k++
        r = substr(c, k + 1); sub(/^[ \t]*/, "", r)
        if (k >= n && r == "") { open = ""; next }
        if (k >= n && inline == 1 && isq(substr(r, 1, 1))) { open = ""; print r; next }
        # The quote that the block follows ends its text, so the block ends there too: a title whose written \n became a
        # line break ends at its closing quote, not at its line. The rest of the line is read again from that quote.
        if (oq == "" || !(j = qend(line, oq))) next
        open = ""; line = substr(line, j) } }' <<<"$3"
}
# breaks <command>: the command with each written `\n` read as bash reads it. In a `$'...'` quote bash makes it a line
# break, so it is one here. Elsewhere (a plain or double quote, or no quote) it stays a backslash and an n, and is
# marked with a \002 byte: no fence starts or ends at it, and no heading starts after it, as the body is one line of
# text to gh. `\\` is a backslash and the next character, so `\\n` is no break and no mark.
breaks() {
  awk '{ s = s (NR > 1 ? "\n" : "") $0 }
    END {
      for (i = 1; i <= length(s); i++) {
        ch = substr(s, i, 1); nx = substr(s, i + 1, 1)
        if (ch == "\\" && nx == "n") { o = o (m == "a" ? "\n" : "\002"); i++; continue }
        # In a plain single quote only `\\` is a pair: a backslash before the closing quote leaves the quote to end it.
        if (ch == "\\" && (m != "s" || nx == "\\")) { o = o ch nx; i++; continue }
        o = o ch
        if (m == "") { if (ch == "\"") m = "d"; else if (ch == q) m = (substr(s, i - 1, 1) == "$" ? "a" : "s") }
        else if ((m == "d" && ch == "\"") || (m != "d" && ch == q)) m = "" }
      printf "%s", o }' q="'" <<<"$1"
}
no_cause() {
  local cmd f t ti=0 fc=
  cmd=$(jq -r '.tool_input.command // ""' <<<"$1" 2>/dev/null) || return 1
  # j: the command with its line continuations (a backslash before a newline) taken out, as Bash reads its words; the
  # words are matched in it, the body text in cmd as written.
  local j=${cmd//$'\\\n'/}
  t=${j//[\"\']/}
  [[ $t =~ (^|[[:space:];\&|])ask[[:space:]]+[^[:space:]]+[[:space:]]+testissue([[:space:]]|$) ]] && ti=1
  files "$1" || [ "$ti" = 1 ] || return 1
  if [[ $cmd =~ (--body-file|-F)[[:space:]=]+[\"\']?([^[:space:]\"\']+) ]] && f=${BASH_REMATCH[2]}; then
    # `--body-file -` reads the body from stdin: a `< file` redirect names that file (stdin_file in lib.sh).
    [ "$f" != - ] || f=$(stdin_file "$cmd") || f=-
    [ ! -f "$f" ] || fc=$(cat "$f" 2>/dev/null)
  fi
  # A heading is its line whole, exactly two hashes, at a line start (up to three spaces before them, as Markdown
  # allows): after a newline or the quote that opens the body, so '### Cause' and a mention of
  # '## What happens now' in a sentence are no heading.
  # A line inside a fenced code block (``` or ~~~) is no heading: the headings are read from the text without its fences.
  local hs=$'(^|\n|["\'])[ ]{0,3}##[[:space:]]+' he=$'[ \t]*(\n|$)' hc c=$cmd inl=1 bq='' hd=$'<<-?[ ]*[\'"]?[A-Za-z_][A-Za-z_0-9]*[\'"]?[ ]*\\)*[ ]*\n'
  # A command with a here-document (`<<WORD` ending its line) holds its body as written: `\n` there is text, and a quote
  # ends nothing; so does a body file (read apart from the command). In an inline body a written `\n` in a `$'...'` quote
  # is a line break; elsewhere it is a backslash and an n, which starts or ends no fence and starts no heading (breaks);
  # `\\n` is a backslash and an n. The quote that opens the body is the one that closes it.
  if [[ $cmd =~ $hd ]]; then inl=0
  else
    # `ask <project> testissue <test file> <title> <body>` has no --body (a `--body` in its text is text): its body is
    # the word after the title. A word is parts with no unquoted space: $'...', '...', "...", a \-escaped character
    # or a bare one. The last group is the quote that opens the body.
    local w="((\\\$'([^'\\\\]|\\\\.)*'|'[^']*'|\"([^\"\\\\]|\\\\.)*\"|\\\\.|\\\$[^'\"[:space:]\\\\]|[^[:space:]'\"\\\\\$])+)"
    if [ "$ti" = 1 ]; then
      [[ ! $j =~ (^|[[:space:];\&|])ask[[:space:]]+${w}[[:space:]]+[\"\']?testissue[\"\']?[[:space:]]+${w}[[:space:]]+${w}[[:space:]]+\$?([\'\"]) ]] \
        || bq=${BASH_REMATCH[-1]}
    else [[ $j =~ (^|[[:space:]])(--body|-b)[[:space:]=]+\$?([\"\']) ]] && bq=${BASH_REMATCH[3]}
    fi
    c=$(breaks "$cmd")
  fi
  hc=$(unfenced "$inl" "$bq" "$c"); hc=${hc//$'\002'/\\n}
  [ -z "$fc" ] || hc+=$'\n'$(unfenced 0 "" "$fc")
  [[ $hc =~ ${hs}Cause${he} ]] && return 1
  [[ $hc =~ ${hs}What\ happens\ now${he} || $ti = 1 ]] && return 0
  grep -qiE "(^|[[:space:]])(--label|-l)(=|[[:space:]]+)?[\"']?([^[:space:]\"']*,)?bug([,\"'[:space:]]|\$)" <<<"$cmd"
}
