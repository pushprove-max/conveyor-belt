#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# The test lint: no test sleeps a set time and then checks that something happened (on a busy machine it has not
# happened yet, and the test fails), and no test the change adds runs the whole loop without saying why (a loop run
# pays for the loop, its sessions and waits). test-changed.sh runs it on every run (in one-file mode in a test step, once
# a tree); test-lint.test.sh is its own test.
# Usage: test-lint.sh [<file>...]   (default: every shell test file under conveyor/ and .claude/scripts/__tests__/:
# each *.test.sh, and the shared files of conveyor/tests/). Exit 1, naming each line, when a line calls sleep and the
# sleep is none of these:
# - the pause of a loop that checks a condition again: `sleep <n>; done`, or the sleep ends its line and the next
#   line is the loop's `done`, in a while or until loop with a condition of its own (not `:`, true or false), or in a
#   loop that leaves by break or return before the pause. A loop that only counts checks nothing, and its pause is a
#   set time: `for i in 1 2 3`, and a while or until whose condition runs no command and reads no file (only `[`,
#   `[[` or `((` over variables and numbers, as `[ "$i" -lt 3 ]`) and whose body sets no variable from a command
#   (`v=$(...)`, read) before the pause;
# - followed at once by the wait helper (wait_until, conveyor/tests/wait.sh), on its line or the next;
# - explained: a `# sleep: <why>` comment on the same line (time is let pass on purpose, or the sleep is a stand-in
#   process the test never waits for). It is a comment of the test file, not quoted text: `echo '# sleep: x'` is none,
#   nor is one in a quoted text begun on a line before, or in the quotes of a `$(...)` inside quoted text. The text of
#   a here-document opens and closes no quoted text of the file: each of its lines is read on its own.
# A comment line is not read. What a sleep is: the word (a line of a script a test writes with printf, after its \n,
# too; called by a path, as /bin/sleep, too, quoted or not), then, after a `--` or not, a number (signed or not, or
# inf), a variable or a command's output, quoted or not.
# It also exits 1, naming each line, when a line this change added or changed (git diff from the merge base of HEAD
# with main to the worktree; every line of a file git does not track) runs the whole loop: `loop run`, `loop serve`,
# `conveyor.sh run` or `conveyor.sh serve`, and no `# loop: <why>` comment, read as `# sleep:` is, is on that line or
# on the line above. A run is the command loop or conveyor.sh (by any path) at the start of a command, after any
# assignments, exec, env, command, nohup, time, timeout <n>, bash or sh. One named in quoted text or in a comment, or
# passed as an argument to another command, is not a run. With no merge base, or nothing changed, this check finds
# nothing.
set -u
cd "$(dirname "$0")/.." || exit 1
if [ $# = 0 ]; then
  mapfile -t files < <(git ls-files -co --exclude-standard 'conveyor/*.sh' '.claude/scripts/__tests__/*.sh' \
    | while read -r f; do case $f in *.test.sh|conveyor/tests/*) [ ! -f "$f" ] || echo "$f" ;; esac; done)
else files=("$@"); fi
[ ${#files[@]} != 0 ] || exit 0
# The lines the change added or changed, <file>:<line> one a line, for the loop check: of each hunk of the diff from
# the merge base with main to the worktree, +<start>[,<count>] (count 1 when left out); of a file git does not track,
# <file>:all. With no merge base, none.
chg=
if base=$(git merge-base HEAD main 2>/dev/null); then
  chg=$({ git diff -U0 --no-color --no-ext-diff --no-prefix "$base" -- "${files[@]}" | awk '/^\+\+\+ / { f = substr($0, 5) }
      /^@@ / { split($3, a, ","); n = (2 in a) ? a[2] : 1; for (i = 0; i < n; i++) print f ":" substr(a[1], 2) + i }'
    git ls-files -o --exclude-standard -- "${files[@]}" | sed 's/$/:all/'; } 2>/dev/null)
fi
# The keys go to awk by a file, not as an argument: one argument holds at most 128 KiB on Linux, and a big diff has more.
bad=$(awk -v kf=<(printf '%s\n' "$chg") '
  BEGIN { while ((getline x < kf) > 0) if (x != "") keep[x] = 1; close(kf) }
  function code(l) { return l !~ /^[ \t]*(#|$)/ }
  # open(s): where in s the innermost loop still open at its end begins (its while, until or for), 0 with none.
  function open(s,   r, base, ms, ml, m, n, st) {
    n = 0; base = 0; r = s
    while (match(r, /(^|[;&|(){}\047\n]|\\n|do|then|else)[ \t]*(while|until|for|done)([^A-Za-z0-9_]|$)/)) {
      ms = RSTART; ml = RLENGTH; m = substr(r, ms, ml)
      if (m ~ /[^a-z]$/) { m = substr(m, 1, length(m) - 1); ml-- }
      match(m, /[a-z]+$/)
      if (substr(m, RSTART) == "done") { if (n) n-- } else st[++n] = base + ms + RSTART - 1
      base += ms + ml - 1; r = substr(r, ms + ml)
    }
    return n ? st[n] : 0
  }
  # checks(pre, i): whether the loop a sleep of line i is in (pre: the line up to the sleep) checks a condition.
  function checks(pre, i,   s, j, at, cond, body, t) {
    s = pre
    for (j = i - 1; !(at = open(s)) && j >= 1 && i - j <= 40; j--) if (code(line[j])) s = line[j] "\n" s
    if (!at) return 0
    s = substr(s, at)
    if (s ~ /(^|[^A-Za-z0-9_])(break|return)([^A-Za-z0-9_]|$)/) return 1
    if (s !~ /^(while|until)[ \t]/ || !match(s, /(;|\n|\\n)[ \t\n]*do([^A-Za-z0-9_]|$)/)) return 0
    cond = substr(s, 1, RSTART - 1); body = substr(s, RSTART + RLENGTH)
    sub(/^(while|until)[ \t]+/, "", cond); gsub(/[$][(][(]/, "", cond); gsub(/[$][(][(]/, "", body)
    if (cond ~ /^(:|true|false)[ \t]*$/) return 0
    # A condition that runs a command, or asks about a file, checks.
    if (cond ~ /[$][(]|`/) return 1
    t = cond; gsub(/\[\[[^]]*\]\]|\[[ \t][^]]*\]|[(][(][^)]*[)][)]/, "", t)
    if (t !~ /^[ \t\n!&|;]*$/) return 1
    t = cond; gsub(/[ \t]-(lt|le|gt|ge|eq|ne|z|n|a|o)[ \t]/, " ", t)
    if (t ~ /[ \t]-[A-Za-z]+[ \t]/) return 1
    # One over variables alone checks only when the loop sets one from a command.
    return body ~ /=["]?([$][(]|`)/ || body ~ /(^|[^A-Za-z0-9_])read[ \t]/
  }
  # says(c, t): whether one of the comments c (as reason gives them) is "# <t>: <why>".
  function says(c, t) { return c ~ ("(^|\001)#[ \t]*" t ":[ \t]*[^ \t\001]") }
  # reason(l): the comments l holds, each after a \001 ("" with none); in cs, l without its comments and with its
  # single-quoted text blanked, and in double-quoted text each ;&|(){}! made a _, so it begins no command (where the
  # loop check looks for a run). A comment begins at a # that begins a word of
  # the code of the test file: "# sleep: <why>" in quoted text is text the test prints, and explains nothing. What is
  # open at the end of a line stays open on the next (ctx, a stack: s and d a single- and a double-quoted text, a a
  # $-quoted one, k a backquoted command, b a ${...}, p a $(...), whose text is code again, with quotes of its own).
  # A here-document (<<WORD, <<-WORD, the word quoted or not) is text too, up to the line that is its word: a quote
  # in it opens nothing in the code after it. Each line of it is read on its own, as a line of a script it may write.
  # here(l, k): the length of the << at k of l and its word, the word kept in hd (tabs: <<-); 0 when it begins no
  # here-document (a shift in a ((...)), or no word after it).
  function here(l, k,   r, a, b, w) {
    a = b = substr(l, 1, k - 1); if (gsub(/[(][(]/, "", a) > gsub(/[)][)]/, "", b)) return 0
    r = substr(l, k + 2)
    if (!match(r, /^-?[ \t]*(\047[^\047]*\047|"[^"]*"|\\?[A-Za-z_][A-Za-z0-9_.-]*)/)) return 0
    w = substr(r, 1, RLENGTH); tabs[++nh] = (w ~ /^-/); sub(/^-?[ \t]*\\?/, "", w); gsub(/["\047]/, "", w); hd[nh] = w
    return RLENGTH + 2
  }
  function reason(l,   k, k0, c, d, x, p, h, w, cmt) {
    p = " "; w = ""; cs = ""
    for (k = 1; k <= length(l); k++) {
      k0 = k; cmt = txt = 0; c = substr(l, k, 1); d = substr(l, k + 1, 1); x = ctx[sp]
      if (x == "s") { if (c == "\047") sp-- }
      else if (c == "\\") k++
      else if (x == "a") { if (c == "\047") sp-- }
      else if (c == "\"") { if (x == "d") sp--; else ctx[++sp] = "d" }
      else if (c == "`") { if (x == "k") sp--; else ctx[++sp] = "k" }
      else if (c == "$" && d == "(") { ctx[++sp] = "p"; dep[sp] = 0; k++; c = d }
      else if (c == "$" && d == "{") { ctx[++sp] = "b"; k++ }
      else if (x == "d") txt = 1
      else if (c == "$" && d == "\047") { ctx[++sp] = "a"; k++ }
      else if (c == "\047") ctx[++sp] = "s"
      else if (x == "b") { if (c == "}") sp-- }
      else if (!body && c == "<" && d == "<" && p != "<" && substr(l, k + 2, 1) != "<" && (h = here(l, k))) { k += h - 1; c = "x" }
      else if (x == "p" && c == "(") dep[sp]++
      else if (x == "p" && c == ")") { if (dep[sp]) dep[sp]--; else sp-- }
      else if (c == "#" && p ~ /[ \t;&|()]/) {
        # In a backquoted command the comment ends at the backquote that closes the command, and code goes on.
        if (x != "k" || !match(substr(l, k), /^([^\\`]|\\.)*`/)) return w "\001" substr(l, k)
        w = w "\001" substr(l, k, RLENGTH - 1)
        k += RLENGTH - 1; sp--; c = "`"; cmt = 1
      }
      p = c
      cs = cs ((x == "s" || x == "a" || cmt) ? " " : (txt && c ~ /[;&|(){}!]/) ? "_" : substr(l, k0, k - k0 + 1))
    }
    return w
  }
  function flush(   i, j, l, rest, nxt, off, pre) {
    sp = 0; ctx[0] = ""; nh = hi = 0
    for (i = 1; i <= n; i++) {
      if (hi == nh) { cm[i] = reason(line[i]); cl[i] = cs; continue }
      l = line[i]; if (tabs[hi + 1]) sub(/^\t+/, "", l)
      if (l == hd[hi + 1]) { hi++; cm[i] = cl[i] = ""; continue }
      j = sp; ctx[++sp] = ""; body = 1; cm[i] = reason(line[i]); cl[i] = cs; body = 0; sp = j
    }
    for (i = 1; i <= n; i++) why[i] = says(cm[i], "sleep")
    # A full-loop run on a line the change added or changed, with no "# loop: <why>" on it or on the line above.
    for (i = 1; i <= n; i++)
      if (code(line[i]) && ((name ":" i) in keep || (name ":all") in keep) && !says(cm[i], "loop") \
          && !(i > 1 && says(cm[i - 1], "loop")) \
          && cl[i] ~ ("(^|[;&|(){}!`]|(^|[^A-Za-z0-9_])(do|then|else)[ \t])[ \t]*" \
            "(([A-Za-z_][A-Za-z0-9_]*=(\"([^\"\\\\]|\\\\.)*\"|[$][(][^)]*[)]|[^ \t\"])*|exec|env|command|nohup|time|timeout[ \t]+[^ \t]+|bash|sh)[ \t]+)*" \
            "[\"\047]?(loop|[^ \t;&|()\"\047]*conveyor\\.sh)[\"\047]?[ \t]+(run|serve)([^A-Za-z0-9_.-]|$)"))
        printf "loop\t%s:%d: %s\n", name, i, line[i]
    for (i = 1; i <= n; i++) {
      l = line[i]
      if (!code(l) || why[i]) continue
      nxt = ""; for (j = i + 1; j <= n; j++) if (code(line[j])) { nxt = line[j]; break }
      rest = l; off = 0
      while (match(rest, /(^|[^A-Za-z0-9_.-]|\\n)sleep["\047]?[ \t]+(--[ \t]+)?["\047]?([$`+]|[0-9.]|inf)/)) {
        pre = substr(l, 1, off + RSTART); off += RSTART + RLENGTH - 1
        rest = substr(rest, RSTART + RLENGTH)
        if (rest ~ /^[^ \t;&|]*[ \t]*;[ \t]*wait_until[ \t]/) continue
        if (rest ~ /^[^ \t;&|]*[ \t]*$/ && nxt ~ /^[ \t]*wait_until[ \t]/) continue
        if ((rest ~ /^[^ \t;&|]*[ \t]*;[ \t]*done([^A-Za-z0-9_]|$)/ \
             || (rest ~ /^[^ \t;&|]*[ \t]*$/ && nxt ~ /^[ \t]*done([^A-Za-z0-9_]|$)/)) && checks(pre, i)) continue
        printf "%s:%d: %s\n", name, i, l; break
      }
    }
    n = 0
  }
  FNR == 1 && NR != 1 { flush() }
  { name = FILENAME; line[++n] = $0 }
  END { flush() }' "${files[@]}") || { echo "test lint: the files could not be read"; exit 1; }
[ -z "$bad" ] && exit 0
loops=$(grep $'^loop\t' <<<"$bad" | cut -f2-); bad=$(grep -v $'^loop\t' <<<"$bad")
if [ -n "$bad" ]; then
  echo "test lint failed: a sleep with a check after it. Wait for the condition (wait_until, conveyor/tests/wait.sh), or say"
  echo "why time must pass in a \"# sleep: <why>\" comment on the same line:"
  echo "$bad"
fi
if [ -n "$loops" ]; then
  echo "test lint failed: a full-loop run (loop run or serve, conveyor.sh run or serve) this change added or changed,"
  echo "with no reason. Call the engine function the test is about, or say what only a whole loop run shows in a"
  echo "\"# loop: <why>\" comment on the line or on the line above:"
  echo "$loops"
fi
exit 1
