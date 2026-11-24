#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases: the build brief's callers and definitions (startbrief(), lib/testmap.sh) with ast-grep installed, a
# search that reads syntax, and without it.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# Main with a bash function fa() (lib/a.sh) called from a `then` line (lib/b.sh) and named after `then` in a comment
# (lib/c.sh); a function fb() defined in a Bats file (tests/h.bats), named after `function` in a string (lib/s.sh) and in
# a comment of another Bats file (tests/old.bats); a function jc() called in Java (src/Y.java) and in shell (lib/b.sh)
# and named in a Java comment after code (src/Z.java); a function kd() named only after `then` in a comment (lib/c.sh);
# a function ctl() called in $( ) (lib/b.sh); a Java method g() (src/Y.java); and a JavaScript arrow function bayEdge()
# (js/s.js). The text search takes each comment for a call and the strings and the comments for definitions, and it
# misses $(ctl), the Java method and the arrow function. The brief of an issue that names all seven is in run.out.
sgbrief() {
  local ISSUE
  setup '[]'
  mkdir -p "$R/lib" "$R/tests" "$R/src" "$R/js" && printf 'fa() { echo a; }\nctl() { :; }\n' > "$R/lib/a.sh" \
    && printf 'if true; then fa; fi\njc 1\nx=$(ctl)\n' > "$R/lib/b.sh" \
    && printf 'x=1 # then fa runs\ny=2 # then kd runs\n' > "$R/lib/c.sh" && printf 'echo "function fb is gone"\n' > "$R/lib/s.sh" \
    && printf 'fb() { :; }\n@test "t" {\n  run fb\n}\n' > "$R/tests/h.bats" && printf '# function fb was here\n' > "$R/tests/old.bats" \
    && printf 'class Y { void g() { jc(1); } }\n' > "$R/src/Y.java" && printf 'class Z { int x = 1; // jc(2) is gone\n}\n' > "$R/src/Z.java" \
    && printf 'const bayEdge = (a) => 1\nbayEdge(2)\n' > "$R/js/s.js" \
    && git -C "$R" add -A && git -C "$R" commit -qm brief || fail "the fixture could not be committed"
  # shellcheck disable=SC2034 # read by the command fx_in() runs
  ISSUE=$(issue 7 2026-01-01 | jq -c '.title = "Change fa(), fb(), jc(), kd(), ctl(), g() and bayEdge()" | .body = ""')
  fx_in 'startbrief "$R" "$ISSUE"'
}

# Bugs: with ast-grep installed, the brief still lists a file that names the function only in a comment as its caller,
# or a string or a comment as its definition; or it only filters what the text search found, so it misses the call in
# $(ctl), the Java method g() and the arrow function bayEdge(); or its syntax search leaves out Java or JavaScript, or
# Bats files, so the text search's comment in tests/old.bats or src/Z.java stays.
# ast-grep is the plugin's bin/ast-grep, which runs the Board's virtualenv's ($XDG_DATA_HOME): here a stand-in that
# prints, for each scan the brief makes (the function the rules name, the files after --), what ast-grep 0.51.3 prints
# for these files with the brief's rules (its JSON lines cut to the fields the brief reads). It fails as a bad rule does
# (exit 8) when the rules have no def and call rule for Bash, Java or JavaScript, and prints nothing with exit 2 for any
# other run: the real parse is ast-grep's own, and the machine that runs the suite need not have it installed. As
# ast-grep does, it counts a rule for a file, and prints the rule's match there, only when the rule's language is the
# file's (Bash for *.sh and *.bats) and no other key (files:, ignores:) narrows it: so a def-bash rule with
# files: ["*.sh"] loses the definition in tests/h.bats, and the case fails.
t_briefsg() {
  local v=$T/$CASE/data/conveyor/board-venv/bin
  mkdir -p "$v" && cat > "$v/ast-grep" <<'EOF' && chmod +x "$v/ast-grep" || fail "the ast-grep stand-in could not be made"
#!/usr/bin/env bash
[ "$1" != --version ] || { echo 'ast-grep 0.51.3'; exit 0; }
[ "$1 $2 $4 $5 $6 $7" = 'scan --inline-rules --json=stream --inspect entity --' ] || { echo "ast-grep stand-in: no answer for: $*" >&2; exit 2; }
for r in def-bash call-bash def-java call-java def-javascript call-javascript; do grep -qx "id: $r" <<<"$3" || { echo "ERROR: no rule $r" >&2; exit 8; }; done
n=$(grep -o "regex: '^[A-Za-z_]*\\$'" <<<"$3" | sort -u) rules=$3
shift 7
# ok <rule id> <file>: the rule applies to the file: its language is the file's and it has only id, language and rule.
ok() {
  local l b
  case $2 in *.java) l=java ;; *.js) l=javascript ;; *.sh | *.bats) l=bash ;; *) return 1 ;; esac
  [ "${1#*-}" = "$l" ] || return 1
  # The whole rule document (from one --- to the next) that holds the id, so a key put before id: is counted too.
  b=$(awk -v id="$1" '/^---$/ { if (f) printf "%s", d; d = ""; f = 0; next } { d = d $0 "\n" } $0 == "id: " id { f = 1 }
    END { if (f) printf "%s", d }' <<<"$rules")
  [ "$(grep -c '' <<<"$b")" = 3 ] && grep -qx "language: $l" <<<"$b" && grep -q '^rule: ' <<<"$b"
}
e() {
  local f l c
  for f in "$@"; do
    case $f in *.java) l=java ;; *.js) l=javascript ;; *) l=bash ;; esac
    c=0; ! ok "def-$l" "$f" || c=$((c + 1)); ! ok "call-$l" "$f" || c=$((c + 1))
    printf 'sg: entity|file|%s: language=%s,appliedRuleCount=%s\n' "$f" "$(case $l in java) echo Java ;; javascript) echo JavaScript ;; *) echo Bash ;; esac)" "$c" >&2
  done
  echo "sg: summary|file: scannedFileCount=$#,skippedFileCount=0" >&2; }
j() { ! ok "$1" "$2" || printf '{"ruleId":"%s","file":"%s","range":{"start":{"line":%s}},"lines":"%s"}\n' "$@"; }
case "$n -- $*" in
  "regex: '^fa\$' -- lib/a.sh lib/b.sh lib/c.sh") e "$@"; j call-bash lib/b.sh 0 'if true; then fa; fi'; j def-bash lib/a.sh 0 'fa() { echo a; }' ;;
  "regex: '^fb\$' -- lib/s.sh tests/h.bats tests/old.bats") e "$@"; j def-bash tests/h.bats 0 'fb() { :; }' ;;
  "regex: '^jc\$' -- lib/b.sh src/Y.java src/Z.java") e "$@"; j call-java src/Y.java 0 'class Y { void g() { jc(1); } }'; j call-bash lib/b.sh 1 'jc 1' ;;
  "regex: '^kd\$' -- lib/c.sh") e "$@" ;;
  "regex: '^ctl\$' -- lib/a.sh lib/b.sh") e "$@"; j call-bash lib/b.sh 2 'x=$(ctl)'; j def-bash lib/a.sh 1 'ctl() { :; }' ;;
  "regex: '^g\$' -- src/Y.java") e "$@"; j def-java src/Y.java 0 'class Y { void g() { jc(1); } }' ;;
  "regex: '^bayEdge\$' -- js/s.js") e "$@"; j def-javascript js/s.js 0 'const bayEdge = (a) => 1'; j call-javascript js/s.js 1 'bayEdge(2)' ;;
  *) echo "ast-grep stand-in: no answer for: $n -- $*" >&2; exit 2 ;;
esac
EOF
  export XDG_DATA_HOME=$T/$CASE/data
  sgbrief
  local want
  for want in '- `fa()`: defined in lib/a.sh; called in lib/b.sh' '- `fb()`: defined in tests/h.bats' \
    '- `jc()`: called in lib/b.sh, src/Y.java' '- `ctl()`: defined in lib/a.sh; called in lib/b.sh' \
    '- `g()`: defined in src/Y.java' '- `bayEdge()`: defined in js/s.js; called in js/s.js'; do
    grep -qxF -e "$want" "$T/$CASE/run.out" \
      || fail "with ast-grep installed, the brief for the fixture of sgbrief() has no line: $want; it is: $(cat "$T/$CASE/run.out")"
  done
  ! grep -qF -e '- `kd()`' "$T/$CASE/run.out" \
    || fail "with ast-grep installed, the brief lists kd(), named only in a comment in lib/c.sh: $(cat "$T/$CASE/run.out")"
}

# Bug: without ast-grep, the brief changed: it must be the text search's, as it was before ast-grep was used, the
# comments and the string listed too, and $(ctl), g() and bayEdge() not found as a call or a definition.
t_briefsgnone() {
  export XDG_DATA_HOME=$T/$CASE/data
  sgbrief
  local want
  for want in '- `fa()`: defined in lib/a.sh; called in lib/b.sh, lib/c.sh' '- `fb()`: defined in lib/s.sh, tests/h.bats, tests/old.bats' \
    '- `jc()`: called in lib/b.sh, src/Y.java, src/Z.java' '- `kd()`: called in lib/c.sh' '- `ctl()`: defined in lib/a.sh'; do
    grep -qxF -e "$want" "$T/$CASE/run.out" \
      || fail "without ast-grep (none under $XDG_DATA_HOME), the brief for the fixture of sgbrief() has no line: $want; it is: $(cat "$T/$CASE/run.out")"
  done
  ! grep -qE -e '^- `(g|bayEdge)\(\)`: defined' "$T/$CASE/run.out" \
    || fail "without ast-grep (none under $XDG_DATA_HOME), the brief finds a definition of g() or bayEdge(), which the text search cannot: $(cat "$T/$CASE/run.out")"
}
