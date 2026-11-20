# SPDX-License-Identifier: Apache-2.0
# The marks of lint-funcs.sh, read from a shell file on stdin: a line `S<TAB><line><TAB><name>` for each line that
# can start a function, and a line `E<TAB><line>` for each line that can end one, in line order. It only marks: bash
# decides what is a function (lint-funcs.sh). POSIX awk only, so that mawk, gawk and the macOS system awk give the
# same marks: no interval expression, no `\` in a bracket expression, `(`, `)` and `}` in brackets.
# - A start: a line that begins, after any indentation, with `name ()` or `function name`, with or without `()`, with
#   any spacing, and whose body opener (`{`, `(`, `if`, `for`, `while`, `until`, `case`, `select` or `[[`) follows on
#   the same line or on the next line that is not blank or a comment. The name is any word bash accepts (`foo+bar`,
#   `a.b`): no blank, quote, `$`, `=`, `#`, brace or shell metacharacter.
# - An end: a line with `}`, `]]`, `fi`, `done` or `esac` standing as a word (after the line's start, a blank, `;`, `&`,
#   `|` or `)`), or with `)` or `))` after any character but `(` and blanks after it (so `( echo one)` ends, and the `)`
#   of `name()` or `name ( )` is none); each followed by the line's end, a blank, `;`, `&`, `|`, `)`, `<`, `>` or `#`.
function opener(s) {
  return s ~ /^([{]|[[][[])([ \t]|$)/ || s ~ /^[(]/ || s ~ /^(if|for|while|until|case|select)([ \t;(]|$)/
}
{
  line = $0
  sub(/^[ \t]+/, "", line)
  # A start whose opener was not on its own line: this line is blank or a comment (wait on), or it opens the body.
  if (pend) {
    if (line != "" && line !~ /^#/) {
      if (opener(line)) printf "S\t%d\t%s\n", pend, pname
      pend = 0
    }
  }
  nm = ""
  if (match(line, /^[^] \t|&;()<>'"`$=#{}[]+/)) {
    nm = substr(line, 1, RLENGTH)
    rest = substr(line, RLENGTH + 1)
    if (nm == "function" && match(rest, /^[ \t]+[^] \t|&;()<>'"`$=#{}[]+/)) {
      nm = substr(rest, 1, RLENGTH)
      sub(/^[ \t]+/, "", nm)
      rest = substr(rest, RLENGTH + 1)
      if (match(rest, /^[ \t]*[(][ \t]*[)]/)) rest = substr(rest, RLENGTH + 1)
    } else if (match(rest, /^[ \t]*[(][ \t]*[)]/)) {
      rest = substr(rest, RLENGTH + 1)
    } else nm = ""
  }
  if (nm != "") {
    sub(/^[ \t]+/, "", rest)
    if (rest == "" || rest ~ /^#/) { pend = NR; pname = nm }
    else if (opener(rest)) printf "S\t%d\t%s\n", NR, nm
  }
  if ($0 ~ /(^|[ \t;&|)])([}]|[]][]]|fi|done|esac)($|[ \t;&|)<>#])/ || $0 ~ /(^|[^( \t])[ \t]*[)]+($|[ \t;&|)<>#])/)
    printf "E\t%d\n", NR
}
