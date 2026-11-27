# SPDX-License-Identifier: Apache-2.0
# FUNCS (read by .conveyor/test-changed.sh: covof, callersof, --funcs for coverage.sh; and by .conveyor/where.sh) reads
# a bash file as its functions and the rest, less strictly than test-changed.sh's CASES: a function starts at a line at
# the left `<name>() {` or `<name>() (` (or `function <name>() ...`), and ends on that line when it closes there, else
# at the next line that starts with the `}` or `)` that closes it, past the heredocs it starts (a heredoc starts at
# `<<<word>` on a line that is not a comment, its word not starting with `-`: `<<123` in a comment and `<<-?` in a
# pattern start none); a line in it may be at the left (a comment, a line of a string). A `{` function with no such `}`
# line before the next function or the end of the file ends at its last indented line that ends with `; }` (or `& }`,
# as a one-line function may end; not a comment), and the lines after it are other lines (issue 1775: `  ...; }` as a
# function's last line). A top-level line (at the left) that ends with `; }` is not such a line, nor is the end of a
# string at the left. A `K<TAB><name><TAB><body>` line for each, its lines joined by \001; `S<TAB><line>` for each
# other line; and `U` when a name is defined twice, a function does not end, or a line in one starts a function before
# such a `; }` line (a function it misread as not ended there).
function heredoc(x) {
  x = $0; gsub(/<<</, "", x)
  if (x !~ /^[ \t]*#/ && match(x, /<<-?[ \t]*[\047"\\]?[A-Za-z_0-9.][A-Za-z_0-9.-]*/)) { x = substr(x, RSTART, RLENGTH); hdt = (x ~ /^<<-/); sub(/^<<-?[ \t]*[\047"\\]?/, "", x); hd = x }
}
function start() { return match($0, /^(function[ \t]+)?[A-Za-z_][A-Za-z0-9_]*[ \t]*\(\)[ \t]*[{(]/) }
function fin(i, k, l) {
  print "K\t" c "\t" cb; k = split(t, l, "\001"); for (i = 2; i <= k; i++) print "S\t" l[i]; c = ""; cb = ""
}
c != "" {
  if (hd != "") { b = b "\001" $0; t = t "\001" $0; x = $0; if (hdt) sub(/^\t+/, "", x); if (x == hd) hd = ""; next }
  if (substr($0, 1, 1) == e) { print "K\t" c "\t" b "\001" $0; c = ""; cb = ""; next }
  if (start()) { if (cb == "") { print "U"; u = 1; exit } fin() }
  else {
    b = b "\001" $0
    if (e == "}" && $0 ~ /^[ \t]+[^ \t#]/ && $0 ~ /[;&] *}([ \t]*[0-9]*>+[ \t]*[^ \t;&|]+)*[ \t]*(#.*)?$/) { cb = b; t = "" } else t = t "\001" $0
    heredoc(); next
  }
}
start() {
  x = substr($0, 1, RLENGTH); e = substr(x, RLENGTH) == "{" ? "}" : ")"; r = substr($0, RLENGTH + 1)
  n = x; sub(/^function[ \t]+/, "", n); sub(/[ \t]*\(.*/, "", n)
  if (n in seen) { print "U"; u = 1; exit }
  seen[n] = 1
  if (r !~ /^[ \t]*(#.*)?$/ && r ~ (e == "}" ? "[;&] *}([ \t]*[0-9]*>+[ \t]*[^ \t;&|]+)*[ \t]*(#.*)?$" : "\\)([ \t]*[0-9]*>+[ \t]*[^ \t;&|]+)*[ \t]*(#.*)?$")) { print "K\t" n "\t" $0; next }
  c = n; b = $0; cb = ""; t = ""; heredoc(); next
}
{ print "S\t" $0 }
END { if (!u && c != "") { if (cb == "") print "U"; else fin() } }
