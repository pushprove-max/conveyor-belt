#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# No engine code splits a whole records file in jq: `bash .conveyor/no-records-split.sh [<file>...]`. jq's split("\n")
# and splits("\n") on the text of a long card records file (27 MB) ran for minutes under the records' lock, and held
# every card's record writes until it was stopped by hand. A reader reads the records a line at a time (jq -R, or
# linesum() in conveyor/lib/records.sh). Exit 1, naming each command, when one jq command takes a records file as one
# text (--rawfile, --arg of its text, or -R with -s, in any form of the flags) and splits it on "\n" (split, splits or
# the / operator, with any blanks or shell escapes): the records are recs, olds, turncards, `stdb ask ... lines`, $READ,
# $READ_OLD, $STATE, $RETRIED, or a file named cards.jsonl or retried.jsonl. One command is read across the lines a
# trailing backslash, |, || or && or an open single quote joins; a whole-line comment is not read. With no file, it
# reads every shell file under conveyor/ that is not a test (conveyor/tests/, *.test.sh) or state (conveyor/state/).
# The project's checks run it (.conveyor/test-changed.sh). no-records-split.test.sh is its own test.
set -u
cd "$(dirname "$0")/.." || exit 1
if [ $# -gt 0 ]; then files=("$@")
else
  mapfile -t files < <(git ls-files -co --exclude-standard -- 'conveyor/*.sh' | grep -v -e '^conveyor/tests/' -e '^conveyor/state/' -e '\.test\.sh$' \
    | while read -r f; do [ -f "$f" ] && echo "$f"; done)
fi
[ ${#files[@]} = 0 ] && exit 0
# A command is flagged when it splits on "\n" and either a --rawfile reads a records file (its path, or a <(...) that
# prints the records and runs no filter on them: grep, awk, sed, jq, head, tail, cut), or an --arg is given their text
# (a "$(...)" of recs, olds, turncards or `stdb ask ... lines`, or with a records path, and no filter), or a jq given -R
# and -s reads one (below).
bad=$(awk '
  function check(   whole, raw, s, i, src, cut, o, t) {
    if (cmd == "") return
    raw = 0; s = cmd
    while ((i = match(s, /--(rawfile|arg)[ \t\n]+[A-Za-z_][A-Za-z0-9_]*[ \t\n]+/)) > 0) {
      o = substr(s, i + 2, 3); s = substr(s, i + RLENGTH); src = s; sub(/^"/, "", src)
      if ((o == "raw" && substr(src, 1, 2) == "<(") || (o == "arg" && substr(src, 1, 2) == "$(")) {
        src = substr(src, 3); if ((i = index(src, ")")) > 0) src = substr(src, 1, i - 1)
        if ((src ~ (o == "raw" ? PROD : RECS) || src ~ PATHS) && src !~ /(^|[ \t(|;&{])(grep|awk|sed|jq|head|tail|cut)[ \t]/) raw = 1 }
      else if (o == "raw") { sub(/[ \t\n].*/, "", src); if (src ~ PATHS) raw = 1 }
    }
    # Each jq of the command: its options, up to its filter (a quote) or a pipe, given -R and -s (one cluster or two).
    whole = 0; t = cmd
    while ((i = match(t, /(^|[ \t\n(|;&{])jq[ \t\n][^|\047]*/)) > 0) {
      o = substr(t, i, RLENGTH); t = substr(t, i + RLENGTH)
      if (o ~ /[ \t\n](-[A-Za-z]*R[A-Za-z]*|--raw-input)([ \t\n\\]|$)/ && o ~ /[ \t\n](-[A-Za-z]*s[A-Za-z]*|--slurp)([ \t\n\\]|$)/) whole = 1
    }
    # The records feed it: a records path in the command, or recs, olds, turncards or `stdb ask ... lines` piped to the
    # jq (across a line break too), or given as its input (< <(...) or <<<"$(...)").
    if (whole) whole = cmd ~ PATHS || cmd ~ /(^|[ \t\n(|;&{])(recs|olds|turncards|stdb ask[^|]* lines [a-z]+)([ \t][^|]*)?\|[ \t\\\n]*jq[ \t\n]/ ||
      cmd ~ /<[ \t]*(<\(|<<[ \t]*"?\$\()[ \t]*(recs|olds|turncards|stdb ask[^|)]* lines )/
    # The split on a newline: "\n", or "\\n" or "\u000a", its quotes escaped or not, read as "NL".
    t = cmd; gsub(/\\+(n|u000[aA])/, "NL", t); gsub(/\\+"/, "\"", t)
    if ((raw || whole) && t ~ /splits?[ \t]*\([ \t]*"NL"[ \t]*[;)]|\/[ \t]*"NL"/) {
      cut = substr(cmd, 1, 160); gsub(/\\\n/, " ", cut); gsub(/[ \t\n]+/, " ", cut); print FILENAME ":" from ": " cut }
    cmd = ""
  }
  BEGIN {
    PROD = "(^|[ \t(|;&{])(recs|olds|turncards|cat)([ \t)|;&}]|$)|stdb ask[^|;]* lines "
    RECS = "(^|[ \t(|;&{])(recs|olds|turncards)([ \t)|;&}]|$)|stdb ask[^|;]* lines "
    PATHS = "\\$\\{?(READ|READ_OLD|STATE|RETRIED)(\\}|#|\"|[ \t)]|$)|(cards|retried)\\.jsonl"
  }
  FNR == 1 { check(); n = 0 }
  n == 0 && /^[ \t]*#/ { next }
  {
    if (n == 0) from = FNR
    # A comment after the code (a # after a blank, outside single quotes) is not read: its apostrophes are no quotes.
    line = $0; p = 0
    while ((i = match(substr(line, p + 1), /[ \t]#/)) > 0) {
      p += i; pre = cmd substr(line, 1, p)
      if (gsub(/\047/, "\047", pre) % 2 == 0) { line = substr(line, 1, p); break }
    }
    cmd = cmd line "\n"; n++
    q = gsub(/\047/, "\047", cmd)
    if ((q % 2 == 1 || line ~ /(\\|\||&&)[ \t]*$/) && n < 60) next
    check(); n = 0
  }
  END { check() }' "${files[@]}")
[ -z "$bad" ] && exit 0
printf '%s\n' "$bad" | sed 's/^/no whole records split in jq (read them a line at a time: jq -R, or linesum()): /' >&2
exit 1
