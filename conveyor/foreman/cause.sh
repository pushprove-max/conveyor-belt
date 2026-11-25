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
    # item: x without its list markers; W is the width they take (0 when none), the indent of the item text, W1 the
    # width of the first, the indent of the text of the outermost item, and I1 the indent of that first marker. Five
    # spaces or more after a marker start an indented code block, so only the first of them goes on the marker. With
    # <para> 1 x goes on a paragraph, so a first ordered marker that does not start at 1 is none.
    # M[1..nm] is the width each marker takes with those before it (the indent of each nested item text).
    function item(x, para,   m, r) {
      W = nm = 0
      while (match(x, /^[ ]?[ ]?[ ]?([-*+]|[0-9]+[.)])[ ][ ]?[ ]?[ ]?/)) {
        m = substr(x, 1, RLENGTH); r = RLENGTH
        if (!W && para && m ~ /^[ ]*[0-9]/ && m !~ /^[ ]*0*1[.)]/) break
        if (substr(x, r + 1, 1) == " ") r -= 3
        if (!W) { W1 = r; match(m, /^[ ]*/); I1 = RLENGTH }
        W += r; M[++nm] = W; x = substr(x, r + 1) }
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
    function fence(line,   c, i, k, w, w1, i1) {
      fq = ""; k = ns
      if (line !~ /^[ \t]*$/) {
        while (k > 0 && S[k] > col(line)) k--
        if (k < ns && !lazy(cut(line, S[k] + 0))) ns = k }
      w = k ? S[k] : 0
      c = item(w ? cut(line, w) : line, P && !L); W += w
      for (i = 1; i <= nm; i++) S[++ns] = w + M[i]
      w = W; w1 = W1; i1 = I1
      if (c ~ /^[`~]/) return c
      if (inline == 1)
        for (i = 1; i < length(line); i++)
          if (isq(substr(line, i, 1)) && (i == 1 || substr(line, i - 1, 1) ~ /[ \t$<]/) &&(c = item(substr(line, i + 1), 0)) ~ /^[`~]/) {
            fq = substr(line, i, 1); return c }
      W = w; W1 = w1; I1 = i1; return "" }
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
            # P: the line before goes on a paragraph; L: that paragraph is in a list, the text of whose last outermost item
            # is at LI. A marker left of LI starts a new outermost item; a paragraph after a blank line that starts left of
            # LI is outside the list.
            if ($0 ~ /^[ \t]*$/ || $0 ~ /^[ ]?[ ]?[ ]?#[#]?[#]?[#]?[#]?[#]?([ \t]|$)/) P = 0
            else if (W) { if (!L || I1 < LI) LI = W1; P = L = 1 }
            else { if (!P && col($0) < LI) L = 0; P = 1 }
            # The line that opens a here-document ends the command text: the body starts a new paragraph.
            if (inline != 1 && $0 ~ /<<-?[ ]*["\047]?[A-Za-z_][A-Za-z_0-9]*["\047]?[ ]*\)*[ ]*$/) P = 0
            print line; next }
          open = ch; n = k; oq = fq; P = 0; if (W) { if (!L || I1 < LI) LI = W1; L = 1 }
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
# uncommented <command>: the command with the text of each shell comment made spaces, as bash reads no word in it: a `#`
# that starts a word outside a quote, up to the end of its line (a backslash there continues no line). A quote in a
# comment then opens no quote, so the quote that opens the body is found after it. A `$(` or a backquote in a double
# quote starts shell text again, as in unquoted (the stack m, depth d; c[d] the open ( in a $(...) part), so a `#` line
# in `"$(cat <<EOF` ... `)"` is a comment; a comment there hides its `)`, but not the backquote that ends a backquote
# part, as Bash finds that end before it reads the comments.
uncommented() {
  awk '{ s = s (NR > 1 ? "\n" : "") $0 }
    END {
      ws = 1; d = 0; m[0] = ""
      for (i = 1; i <= length(s); i++) {
        ch = substr(s, i, 1); nx = substr(s, i + 1, 1); t = m[d]
        if (t == "c" && ch == "`" && m[d - 1] == "b") { d -= 2; o = o ch; continue }
        if (t == "c") { if (ch == "\n") { d--; ws = 1 } else ch = " "; o = o ch; continue }
        # ws: the character before ends a word (a blank or an operator outside a quote, with no backslash before it); a
        # line continuation (a backslash before a newline) is no character, so it keeps ws.
        sh = t == "" || t == "p" || t == "b"
        if (sh && ch == "#" && ws) { m[++d] = "c"; o = o " "; continue }
        if (ch == "\\" && t != "s") { o = o ch nx; i++; if (nx != "\n") ws = 0; continue }
        o = o ch
        if (t == "d" && ch == "$" && nx == "(") { m[++d] = "p"; c[d] = 0; o = o nx; i++; ws = 1; continue }
        if (t == "d" && ch == "`") { m[++d] = "b"; ws = 1; continue }
        if (sh) {
          ws = ch ~ /[ \t\n;&|()<>]/
          if (ch == "\"") m[++d] = "d"; else if (ch == q) m[++d] = (substr(s, i - 1, 1) == "$" ? "a" : "s")
          else if (t == "b" && ch == "`") d--
          else if (t == "p" && ch == "(") c[d]++
          else if (t == "p" && ch == ")") { if (c[d]) c[d]--; else d-- } }
        else if ((t == "d" && ch == "\"") || (t != "d" && ch == q)) { d--; ws = 0 } }
      printf "%s", o }' q="'" <<<"$1"
}
# unquoted <command>: the command with the text in each quote made x (the quote marks kept), so a `<<WORD` written in a
# quote (`echo 'Use <<EOF'`) is no here-document. A `$(` or a backquote in a double quote starts shell text again, up to
# its own `)` or backquote, so the `<<'EOF'` of `--body "$(cat <<'EOF'` stays. d: the depth of the stack m of what each
# open part is ("" shell text, s '...', a $'...', d "...", p $(...), b `...`); c[d]: the open ( in a $(...) part.
unquoted() {
  awk '{ s = s (NR > 1 ? "\n" : "") $0 }
    END {
      d = 0; m[0] = ""
      for (i = 1; i <= length(s); i++) {
        ch = substr(s, i, 1); nx = substr(s, i + 1, 1); t = m[d]
        if (t == "s") { if (ch == q) { d--; o = o ch } else o = o "x"; continue }
        if (t == "a" || t == "d") {
          if (ch == "\\") { o = o "xx"; i++; continue }
          if ((t == "a" && ch == q) || (t == "d" && ch == "\"")) { d--; o = o ch; continue }
          if (t == "d" && ch == "$" && nx == "(") { m[++d] = "p"; c[d] = 0; o = o ch nx; i++; continue }
          if (t == "d" && ch == "`") { m[++d] = "b"; o = o ch; continue }
          o = o "x"; continue }
        o = o ch
        if (ch == "\\") { o = o nx; i++; continue }
        if (ch == q) m[++d] = (substr(s, i - 1, 1) == "$" ? "a" : "s")
        else if (ch == "\"") m[++d] = "d"
        else if (t == "b" && ch == "`") d--
        else if (t == "p" && ch == "(") c[d]++
        else if (t == "p" && ch == ")") { if (c[d]) c[d]--; else d-- } }
      printf "%s", o }' q="'" <<<"$1"
}
# heredocs <command>: the command as Bash reads its here-documents: each body as written (a `#` line in it is Markdown,
# a quote ends nothing), and the shell text around the bodies with its comments made spaces (uncommented), so a
# `## Cause` comment after a body is no heading. A body starts on the line after the one (with its line continuations)
# that holds its `<<WORD`, and ends at a line that is only WORD (tabs before it taken off for a `<<-`). A blank line goes
# before the bodies and in place of each end word, so a body starts and ends a paragraph. The text after the bodies is
# read again from its start, as Bash reads it. With a second argument `0`, the bodies are left out (each is one blank
# line): only the shell text stays, where the options are read, so a quote or a `#` in a body changes no comment after it.
heredocs() {
  # LC_ALL=C (exported to the awks): the awk below and Bash's ${u:0:at} and ${s:at} all count bytes. In a UTF-8 locale
  # mawk counts bytes and Bash counts characters, so each multibyte character before a `<<WORD` line moved the cut into
  # the body.
  local -x LC_ALL=C
  local s=$1 nb=${2:-1} o='' r='' u q ru rq at ops op w line
  while [ -n "$s" ]; do
    # r: the shell text read so far, without the bodies. The text after a body is read on from it, not from a new
    # start, so a quote open when the body began (`"$(cat <<EOF` ... `)"`) is still open: its closing `"` opens none,
    # and a `#` after it starts a comment. The part read from r (ru, rq; an x after it keeps its last newline) is cut
    # off the front, not a count of characters, as awk can count bytes where bash counts characters.
    u=$(uncommented "$r$s") at='' ops=''
    q=$(unquoted "$u")
    if [ -n "$r" ]; then
      ru=$(uncommented "${r}x"); ru=${ru%x}; rq=$(unquoted "${ru}x"); rq=${rq%x}
      u=${u#"$ru"}; q=${q#"$rq"}
    fi
    # at: where the first line that holds a `<<WORD` outside quotes ends (its newline); ops: the words of its `<<WORD`s,
    # with a `-` before each one of a `<<-`. A run of `<` is counted across line continuations: three are a here-string.
    read -r at ops < <(U=$u Q=$q awk 'BEGIN {
      q = ENVIRON["Q"]; u = ENVIRON["U"]; n = length(q)
      for (i = 1; i <= n; i++) {
        ch = substr(q, i, 1)
        if (ch == "\\") { i++; continue }
        if (ch == "\n") { if (ops != "") { print i, ops; exit } continue }
        if (ch != "<") continue
        for (k = 0; i <= n; )
          if (substr(q, i, 1) == "<") { k++; i++ } else if (substr(q, i, 2) == "\\\n") i += 2; else break
        d = ""; if (substr(q, i, 1) == "-") { d = "-"; i++ }
        while (substr(q, i, 1) ~ /[ \t]/) i++
        if (k == 2 && match(substr(u, i), /^["\047]?[A-Za-z_][A-Za-z_0-9]*/)) {
          w = substr(u, i, RLENGTH); gsub(/["\047]/, "", w); ops = ops " " d w; i += RLENGTH }
        i-- } }')
    if [ -z "$at" ]; then o+=$u; break; fi
    o+=${u:0:at}$'\n'; r+=${s:0:at}; s=${s:at}
    for op in $ops; do
      w=${op#-}
      while [ -n "$s" ]; do
        line=${s%%$'\n'*}
        if [[ $s == *$'\n'* ]]; then s=${s#*$'\n'}; else s=''; fi
        if [ "$op" != "$w" ]; then while [[ $line == $'\t'* ]]; do line=${line:1}; done; fi
        if [ "$line" = "$w" ]; then o+=$'\n'; break; fi
        [ "$nb" = 0 ] || o+=$line$'\n'
      done
    done
  done
  printf '%s' "$o"
}
no_cause() {
  local cmd f t ti=0 fc=
  cmd=$(jq -r '.tool_input.command // ""' <<<"$1" 2>/dev/null) || return 1
  # u: the command with its shell comments made spaces (uncommented), as bash reads no word in them. o: u with its
  # here-document bodies left out (heredocs), so a quote in a body (`It's`) opens no quote that hides a comment after the
  # body. The options (`ask ... testissue`, `--body-file`, its `< file`, `--label`) are read in o: one written in a
  # comment or a body is none.
  local u uq o
  u=$(uncommented "$cmd")
  o=$(heredocs "$cmd" 0)
  # j: o with its line continuations (a backslash before a newline) taken out, as Bash reads its words; an
  # `ask <project> testissue` is matched in it.
  local j=${o//$'\\\n'/}
  t=${j//[\"\']/}
  [[ $t =~ (^|[[:space:];\&|])ask[[:space:]]+[^[:space:]]+[[:space:]]+testissue([[:space:]]|$) ]] && ti=1
  files "$1" || [ "$ti" = 1 ] || return 1
  if [[ $o =~ (--body-file|-F)[[:space:]=]+[\"\']?([^[:space:]\"\']+) ]] && f=${BASH_REMATCH[2]}; then
    # `--body-file -` reads the body from stdin: a `< file` redirect names that file (stdin_file in lib.sh).
    [ "$f" != - ] || f=$(stdin_file "$o") || f=-
    [ ! -f "$f" ] || fc=$(cat "$f" 2>/dev/null)
  fi
  # A heading is its line whole, exactly two hashes, at a line start (up to three spaces before them, as Markdown
  # allows): after a newline or the quote that opens the body, so '### Cause' and a mention of
  # '## What happens now' in a sentence are no heading.
  # A line inside a fenced code block (``` or ~~~) is no heading: the headings are read from the text without its fences.
  local hs=$'(^|\n|["\'])[ ]{0,3}##[[:space:]]+' he=$'[ \t]*(\n|$)' hc='' hd=$'(^|[^<])<<-?[ ]*[\'"]?[A-Za-z_][A-Za-z_0-9]*[\'"]?[ ]*\\)*[ ]*\n'
  # A command with a here-document (`<<WORD` ending its line) holds its body as written: `\n` there is text, and a quote
  # ends nothing; so does a body file (read apart from the command). In an inline body a written `\n` in a `$'...'` quote
  # is a line break; elsewhere it is a backslash and an n, which starts or ends no fence and starts no heading (breaks);
  # `\\n` is a backslash and an n. The quote that opens the body is the one that closes it.
  # In u a quote, a `<<WORD` or a heading in a comment is read as none. An inline body is found and read in u; a here-document body is read from cmd, as a `#` line in it
  # is Markdown, not a comment, and the text around it from u (heredocs). The `<<WORD` is looked for outside quotes (unquoted): one in a quote is text. A `<<<` is
  # a here-string, no here-document: its last two `<` start none. uq: the unquoted text with its line continuations
  # taken out after the quotes are made x (one in a quote is text), as Bash joins `<\` at a line end and a next-line
  # `<<` into one `<<<`.
  uq=$(unquoted "$u"); uq=${uq//$'\\\n'/}
  if [[ $uq =~ $hd ]]; then hc=$(unfenced 0 "" "$(heredocs "$cmd")")
  else
    # `ask <project> testissue <test file> <title> <body>` has no --body (a `--body` in its text is text): its body is
    # the word after the title. A word is parts with no unquoted space: $'...', '...', "...", a \-escaped character
    # or a bare one. The last group is the quote that opens the body. The words before `ask` or `--body` are matched
    # whole from the command start (pre), so an `ask ... testissue` or a `--body "` written inside a quote (a gh title)
    # is text: the body quote comes from the real `--body`.
    local w="((\\\$'([^'\\\\]|\\\\.)*'|'[^']*'|\"([^\"\\\\]|\\\\.)*\"|\\\\.|\\\$[^'\"[:space:]\\\\]|[^[:space:]'\"\\\\\$])+)"
    local pre="^(([[:space:];&|]|${w})*[[:space:];&|])?" rest n at r i e qs=() ats=()
    local ask="ask[[:space:]]+${w}[[:space:]]+[\"\']?testissue[\"\']?[[:space:]]+${w}[[:space:]]+${w}[[:space:]]+"
    # A command that files more than one issue has a body quote for each: the longest match finds the last body, and
    # the text before it is searched again. Each body is read from its `--body` (or `ask`) word with its own quote, so
    # one body's quote is never used to read another's fences. at: where that word starts in u, as rest has no line
    # continuations (each is two characters fewer in rest).
    rest=${u//$'\\\n'/}
    # A `<<<` here-string opens a body too, as it is the stdin of `--body-file -`: its quote is the one that closes it.
    # Bash needs no space before `<<<` (`-<<<'...'`), so a word may touch it.
    while [[ $rest =~ ${pre}(${ask}|(--body|-b)[[:space:]=]+|${w}?<<<[[:space:]]*)\$?([\'\"]) ]]; do
      n=${#BASH_REMATCH[1]}; qs=("${BASH_REMATCH[-1]}" "${qs[@]}"); rest=${rest:0:n}
      at=$n; r=${u:0:at}; r=${r//$'\\\n'/}
      while [ "${#r}" -lt "$n" ]; do at=$((at + n - ${#r})); r=${u:0:at}; r=${r//$'\\\n'/}; done
      ats=("$at" "${ats[@]}")
    done
    # The text before the first body is read with it; with no body quote found, either quote may open the body.
    [ "${#qs[@]}" -gt 0 ] || qs=('')
    ats[0]=0
    for i in "${!qs[@]}"; do
      e=${ats[i + 1]:-${#u}}
      hc+=$(unfenced 1 "${qs[i]}" "$(breaks "${u:ats[i]:e - ats[i]}")")$'\n'
    done
  fi
  hc=${hc//$'\002'/\\n}
  [ -z "$fc" ] || hc+=$'\n'$(unfenced 0 "" "$fc")
  [[ $hc =~ ${hs}Cause${he} ]] && return 1
  [[ $hc =~ ${hs}What\ happens\ now${he} || $ti = 1 ]] && return 0
  grep -qiE "(^|[[:space:]])(--label|-l)(=|[[:space:]]+)?[\"']?([^[:space:]\"']*,)?bug([,\"'[:space:]]|\$)" <<<"$o"
}
