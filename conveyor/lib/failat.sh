# SPDX-License-Identifier: Apache-2.0
# Where a test failed, read from the stack traces in its output: the place of a failing case or file of a card's run
# (atsource(), for testfails() in lib/testrun.sh) and of the push check's output (failat(), lib/push.sh and
# lib/pushrun.sh), with the text of that line.
# testfails()'s record on stdin, with each place a case or a file failed at ($at, $fat) given its line's text, read
# from <worktree> (wtline()): a case's line ends with ` (at <file>:<line>: <text>)`, a file's at is that place.
atsource() { # <worktree>
  local in a n t src=()
  in=$(cat)
  while IFS=$'\t' read -r a n; do
    t=$(wtline "$1" "$a" "$n" | tr -d '\000\r\t'); src+=("$a:$n"$'\t'"$t")
  done < <(jq -r '[.files[] | (.cases[].at // empty), (.at // empty) | @tsv] | unique[]' <<<"$in")
  jq -c --rawfile s <(printf '%s\n' "${src[@]}") '([$s | split("\n")[] | select(. != "") | split("\t")
      | {key: .[0], value: (.[1] // "" | gsub("^\\s+|\\s+$"; "") | if length > 120 then .[0:119] + "…" else . end)}] | from_entries) as $s
    | def place: "\(.[0]):\(.[1])" as $k | $k + (if ($s[$k] // "") != "" then ": \($s[$k])" else "" end);
    .files |= map((.cases |= map(if .at then (.at | place) as $p | del(.at) | .line += " (at \($p))" else . end))
      | if .at then .at |= place else . end)' <<<"$in"
}
# A frame of a stack trace in a test's output, as a JavaScript engine prints one (node, bun, jest): `at <fn>
# (<path>:<line>:<column>)` or `at <path>:<line>:<column>`, or the same with no `at` (node's TAP stack), a file://
# URL as a path; the frame that ends a stack may end with ` {`. p is the absolute path, n the line (testfails(), failat()).
FRAMERX='^\s*(?:at\s+)?(?:.*\()?(?:file://)?(?<p>/[^():]*[^():\s]):(?<n>[0-9]+):[0-9]+\)?(?:\s*\{)?\s*$'
# A frame of a Python traceback (python3, unittest): `File "<path>", line <line>, in <fn>`, p the absolute path, n the line.
PYFRAMERX='^\s*File "(?<p>/[^"]+)", line (?<n>[0-9]+)(?:, in .*)?$'
# The jq of a frame, with $rx (FRAMERX), $pyrx (PYFRAMERX), $wd and $wdr (the worktree, as given and its physical path)
# (testfails(), failat()). frame: of a line, null when it is no frame, else {f, n, py}: f the path in the worktree
# (null for a frame of a file outside it or under node_modules), n the line, py whether it is Python's. A stack's place
# is its first frame in the worktree (a JavaScript stack starts with the frame that threw); a Python traceback's is
# its last one (it ends with that frame), read at the end of the traceback: pyend(<line>), its exception line, the first
# that starts with no space and is no `Traceback` header.
FRAMEJQ='def frame: [(capture($rx) | . + {py: false}), (select($pyrx != "") | capture($pyrx) | . + {py: true})][0] | if . == null then null else . as $m | (first([$wdr, $wd][] | . as $x | select($x != "" and ($m.p | startswith($x + "/")))) // null) as $d | (if $d then $m.p[($d | length) + 1:] else null end) as $f | {f: (if $f and ($f | test("(^|/)(node_modules|\\.\\.)(/|$)") | not) then $f else null end), n: $m.n, py: $m.py} end; def pyend($l): ($l | test("^\\S")) and ($l | test("^Traceback ") | not);'
# Line <n> of <file>, a path in <dir>: only of a regular file whose path below <dir> has no symbolic link in it, as one
# there (a commit's, or one a test made) could name a file outside <dir>, which a failure report would then show
# (testfails(), failat()). Prints nothing else.
wtline() { # <dir> <file> <n>
  local p=$1 x parts=()
  [[ $3 =~ ^[0-9]+$ ]] || return 1
  IFS=/ read -r -a parts <<<"$2"
  for x in "${parts[@]}"; do
    [ -n "$x" ] && [ "$x" != . ] || continue
    [ "$x" != .. ] || return 1
    p+=/$x; [ ! -L "$p" ] || return 1
  done
  [ -f "$p" ] && sed -n "${3}{p;q;}" "$p" 2>/dev/null
}
# Where the failures of a test's output (stdin) are, as testfails() reads them for a case's line, for an output that
# is no card's run (the push check: lib/push.sh): the place of each stack trace (FRAMEJQ: a JavaScript stack's first
# frame in a file of <worktree>, a Python traceback's last), as `<file>:<line>: <that line's text>` (trimmed, cut to
# 120 characters), each once, at most 5. The text is read from <commit> when it is given (the worktree may be gone),
# else from the worktree (wtline()). Prints nothing when there is none.
failat() { # <worktree> [<commit>]
  local w wr a n t
  w=$(cd "$1" 2>/dev/null && pwd) && wr=$(cd "$1" && pwd -P) || { w=$1; wr=$1; }
  while IFS=$'\t' read -r a n; do
    if [ -n "${2:-}" ]; then t=$(git cat-file -p "$2:$a" 2>/dev/null | sed -n "${n}{p;q;}"); else t=$(wtline "$w" "$a" "$n"); fi
    t=$(printf '%s' "$t" | tr -d '\000\r' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
    [ ${#t} -le 120 ] || t="${t:0:119}…"
    printf '%s:%s%s\n' "$a" "$n" "${t:+: $t}"
  done < <(sed 's/\x1b\[[0-9;]*m//g' | tr -d '\000\r' | jq -rRn --arg rx "$FRAMERX" --arg pyrx "$PYFRAMERX" --arg wd "$w" --arg wdr "$wr" "$FRAMEJQ"'
    # got: the JavaScript stack read now has given its place; py: the last place of the Python traceback read now.
    [foreach (inputs, "\u0000") as $l ({got: false, py: null, out: null};
      .out = null | ($l | frame) as $fr
      | (if .py and pyend($l) then .out = .py | .py = null else . end)
      | if $fr == null then .got = false
        elif $fr.f == null or .got then .
        elif $fr.py then .py = [$fr.f, $fr.n]
        else .got = true | .out = [$fr.f, $fr.n] end;
      .out // empty | @tsv)] | reduce .[] as $x ([]; if IN(.[]; $x) then . else . + [$x] end) | .[0:5][]')
}
