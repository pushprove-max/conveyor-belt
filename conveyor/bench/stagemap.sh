#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Benchmark phase 0: the stage map. For each stage of a card (build, review, fix, test, land, push) it follows, from
# the engine functions that run the stage, every function they call, or pass to a function that runs its arguments
# (apitries "$1" review "$1.events" claudereview ...: apitries runs "$4"), and every global they read, over the
# engine's lib/*.sh, and prints each engine file the stage reaches: the files
# that define them, and the rules, jq, schema or lib data files a global or a function names under the engine folder
# ($HERE/rules/card-core.md, for example).
# A stage check replays one stage only when the changed files reach that stage alone; a file this map gives to several
# stages widens the check to each of them, and a changed engine file the map does not list is unknown, which widens
# the check to every stage.
# Words in quotes and comments are text, not calls: only code is read, with the code of a $( ) inside double quotes,
# and the $NAME globals a double-quoted string or an unquoted here-document reads. Nor is a variable a call, a case
# pattern or a word of a [ ] or [[ ]] test. A function named only through a variable ("$cmd" ...) is not seen.
# Usage: stagemap.sh [--shared] [<engine folder>]   (default: the conveyor/ folder above this script)
# Prints `<file>\t<stage>,<stage>...`, the file relative to the engine folder, sorted; with --shared, only the files of
# two or more stages. Read-only.
set -euo pipefail
SHARED=''; [ "${1:-}" != --shared ] || { SHARED=1; shift; }
E=$(cd "${1:-$(dirname "$0")/..}" && pwd -P)
[ -d "$E/lib" ] || { echo "stagemap: $E has no lib folder" >&2; exit 1; }
# Each stage and the engine functions and globals that run it. Build and fix are both session() with a step argument;
# fix adds its findings text (FIX) and the review of a fix (rereview). card() builds the prompt of a model stage before
# it calls the stage: the brief (brief) and the card rules (cardrules, rules/card-core.md), and the review's
# instructions (REVIEWT).
STAGES='build session brief cardrules
review reviewed brief cardrules REVIEWT
fix session rereview brief cardrules FIX
test tests
land land
push push'
shopt -s nullglob
LIBS=()
for f in "$E"/lib/*.sh; do [[ $f == *.test.sh ]] || LIBS+=("${f#"$E"/}"); done
[ ${#LIBS[@]} -gt 0 ] || { echo "stagemap: $E/lib holds no engine file" >&2; exit 1; }
(cd "$E" && awk -v stages="$STAGES" '
  # scan(): the code words of one line, in W[1..WN], the quote state carried over from the line before (top, md[],
  # dp[]: a stack of C code, S single quotes, A $'"'"'...'"'"', D double quotes). In D, a word right after $ is a global read.
  # A word of code is kept as a name it uses when it is a command (cp: at the start of a statement), or an argument of
  # a command (cmd) that is an engine function or runs its arguments (apitries "$1" review ... claudereview; kept as
  # "~cmd~word", read once every function is known). Left out: a variable it sets (w=, w+=, w[), a name a local,
  # declare, read or for statement declares, and a variable it reads ($w, ${w), kept as "$w": the read of a global.
  function emit(c, nx,   t) {
    if (w == "") return
    t = w; w = ""
    if (wd) { W[++WN] = "$" t; return }
    if (c == "=" || c == "[" || (c == "+" && nx == "=")) return
    if (decl == 2) { decl = 0; return }
    if (decl == 1 && wa) return
    if (cp && t ~ /^(if|then|else|elif|do|while|until|time|function)$/) return
    if (t ~ /^(local|declare|readonly|read)$/) { decl = 1; cp = 0; cmd = t; return }
    if (t == "for") { decl = 2; cp = 0; cmd = t; return }
    if (cp && (opt || t ~ /^[0-9]+$/ || t ~ /^(exec|timeout|command|nohup|env)$/)) return # the command is still to come
    if (cp && (c == ")" || c == "|") && top == 1 && dp[1] == 0) return # a case pattern (codexreview) ...)
    if (cp) { cp = 0; cmd = t; W[++WN] = t; return }
    W[++WN] = "~" cmd "~" t
  }
  function scan(s,   i, c, n, m, prev) {
    WN = 0; w = ""; n = length(s); prev = " "; decl = 0; cp = 1; cmd = ""; inb = 0
    for (i = 1; i <= n; i++) {
      c = substr(s, i, 1); m = md[top]
      if (m == "S") { if (c == "'"'"'") top--; prev = c; continue }
      if (m == "A") { if (c == "\\") i++; else if (c == "'"'"'") top--; prev = c; continue }
      if (m == "D") {
        if (c == "\\") { i++; prev = " "; continue }
        if (c == "\"") { emit(c); top--; prev = c; continue }
        if (c == "$" && substr(s, i + 1, 1) == "(") { emit(c); md[++top] = "C"; dp[top] = 0; i++; prev = "("; cp = 1; cmd = ""; continue }
        if (c ~ /[A-Za-z0-9_]/) { if (w != "" || prev == "$" || prev == "{" || prev == "#" || prev == "!") { if (w == "") wd = 1; w = w c }; if (w == "") prev = c; continue }
        emit(c); prev = (c == "{" && prev == "$") ? "{" : ((c == "#" || c == "!") && prev == "{") ? c : c == "{" ? " " : c
        continue
      }
      # code
      if (c ~ /[A-Za-z0-9_]/) {
        if (w == "") { wd = (prev == "$" || prev == "{" || prev == "#" || prev == "!") && dl; wa = (prev ~ /[ \t]/); opt = (prev == "-" || prev == "=") }
        w = w c; prev = c; continue
      }
      emit(c, substr(s, i + 1, 1))
      if (c ~ /[;&|)]/) decl = 0
      # A test ([ ] or [[ ]]) holds no command: its ( | ! (a regex, a negation) start none.
      if (c ~ /[;&|({!]/ && !inb) { cp = 1; cmd = "" }
      if (c == "[" && cp) { cp = 0; cmd = "["; inb = 1 }
      if (c == "]") inb = 0
      dl = (c == "$") || (dl && c == "{" && prev == "$") || (dl && (c == "#" || c == "!") && prev == "{")
      if (c == "\\") { i++; prev = " "; continue }
      if (c == "#" && (prev ~ /[ \t;&|(]/)) break
      if (c == "$" && substr(s, i + 1, 1) == "'"'"'") { md[++top] = "A"; i++; prev = " "; continue }
      if (c == "'"'"'") { md[++top] = "S"; prev = c; continue }
      if (c == "\"") { if (cp && substr(s, i + 1) ~ /^\$\{?[@0-9]/) runs = 1; md[++top] = "D"; prev = c; continue }
      if (c == "(") dp[top]++
      if (c == ")") { if (dp[top] == 0 && top > 1) { top--; prev = c; continue } if (dp[top] > 0) dp[top]-- }
      prev = c
    }
    emit(" ")
  }
  function datafiles(s, key,   r) { # the files a line names under the engine folder ($HERE/... or $SRC/...)
    while (match(s, /\$\{?(HERE|SRC)\}?\/(rules|jq|schema|lib)\/[A-Za-z0-9_.\/-]+/)) {
      r = substr(s, RSTART, RLENGTH); sub(/^\$\{?(HERE|SRC)\}?\//, "", r); sub(/[.]$/, "", r)
      files[key] = files[key] " " r; s = substr(s, RSTART + RLENGTH)
    }
  }
  function keep(key,   i) {
    for (i = 1; i <= WN; i++) uses[key] = uses[key] " " W[i]
    if (runs) runsargs[key] = 1; runs = 0
  }
  FNR == 1 { fn = ""; last = ""; hd = ""; top = 1; md[1] = "C"; dp[1] = 0 }
  hd != "" { # a here-document: its end line, or a line whose globals an unquoted one reads
    t = $0; if (hdt) sub(/^\t+/, "", t)
    if (t == hd) { hd = ""; next }
    if (!hdq) { s = $0; while (match(s, /\$\{?[A-Za-z_][A-Za-z0-9_]*/)) { v = substr(s, RSTART, RLENGTH); gsub(/[^A-Za-z0-9_]/, "", v); uses[key] = uses[key] " " v; s = substr(s, RSTART + RLENGTH) } }
    datafiles($0, key); next
  }
  top == 1 && /^[[:space:]]*#/ { next }
  top == 1 && fn == "" && /^[A-Za-z_][A-Za-z0-9_]*\(\) *\{/ {
    name = $0; sub(/\(.*/, "", name); def[name] = FILENAME; key = "f" SUBSEP name; last = ""
    rest = $0; sub(/^[^{]*\{/, "", rest); scan(rest); keep(key); datafiles(rest, key)
    code = rest; sub(/[[:space:]]#[[:space:]].*$/, "", code)
    if (top == 1 && code ~ /\}[[:space:]]*$/) next # a one-line function
    fn = name; next
  }
  top == 1 && fn != "" && /^\}/ { fn = ""; next }
  top == 1 && fn == "" && /^[A-Z_][A-Z0-9_]*=/ { # a global, and what its value reads, to the end of the value
    v = $0; sub(/=.*/, "", v); gdef[v] = FILENAME; key = "g" SUBSEP v; last = v
    val = $0; sub(/^[^=]*=/, "", val); scan(val); keep(key); datafiles(val, key); next
  }
  {
    if (fn == "" && top == 1 && last == "") next # top-level code that is no function and no global
    if (fn == "" && top == 1 && $0 !~ /^[[:space:]]/) { last = ""; next }
    scan($0); keep(key); datafiles($0, key)
    if (top == 1 && match($0, /<<-?[[:space:]]*['"'"'"]?[A-Za-z_]+['"'"'"]?/)) {
      hd = substr($0, RSTART, RLENGTH); hdt = (hd ~ /^<<-/); hdq = (hd ~ /['"'"'"]/); sub(/^<<-?[[:space:]]*/, "", hd); gsub(/['"'"'"]/, "", hd)
    }
  }
  END {
    ns = split(stages, sl, "\n")
    for (s = 1; s <= ns; s++) {
      n = split(sl[s], e, " "); stage = e[1]; order[s] = stage; split("", seen); split("", q); qn = 0
      for (i = 2; i <= n; i++) {
        if (e[i] in def) { q[++qn] = "f" SUBSEP e[i]; seen["f" SUBSEP e[i]] = 1 }
        else if (e[i] in gdef) { q[++qn] = "g" SUBSEP e[i]; seen["g" SUBSEP e[i]] = 1 }
        else { print "stagemap: the stage " stage " names " e[i] ", which no engine file defines" > "/dev/stderr"; bad = 1 }
      }
      for (k = 1; k <= qn; k++) {
        split(q[k], kv, SUBSEP); at[(kv[1] == "f" ? def[kv[2]] : gdef[kv[2]]), stage] = 1
        m = split(files[q[k]], fl, " "); for (i = 1; i <= m; i++) at[fl[i], stage] = 1
        m = split(uses[q[k]], u, " ")
        for (i = 1; i <= m; i++) {
          if (substr(u[i], 1, 1) == "~") { split(u[i], a, "~"); if (!(("f" SUBSEP a[2]) in runsargs)) continue; u[i] = a[3] }
          if (substr(u[i], 1, 1) == "$") { u[i] = substr(u[i], 2); if ((u[i] in gdef) && !(("g" SUBSEP u[i]) in seen)) { seen["g" SUBSEP u[i]] = 1; q[++qn] = "g" SUBSEP u[i] }; continue }
          if ((u[i] in def) && !(("f" SUBSEP u[i]) in seen)) { seen["f" SUBSEP u[i]] = 1; q[++qn] = "f" SUBSEP u[i] }
          if ((u[i] in gdef) && !(("g" SUBSEP u[i]) in seen)) { seen["g" SUBSEP u[i]] = 1; q[++qn] = "g" SUBSEP u[i] }
        }
      }
    }
    if (bad) exit 1 # a map without one of its stages would leave that stage out of every check
    for (k in at) { split(k, kv, SUBSEP); fset[kv[1]] = 1 }
    for (f in fset) {
      out = ""; c = 0
      for (s = 1; s <= ns; s++) if ((f, order[s]) in at) out = out (c++ ? "," : "") order[s]
      print f "\t" out "\t" c
    }
  }' "${LIBS[@]}") | sort | awk -F'\t' -v shared="$SHARED" 'shared == "" || $3 > 1 { print $1 "\t" $2 }'
