#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300 -- about 193s run alone on the Mac (2026-09-27)
# Self-test for bash-guardrails.sh. Run directly.
set -u
export CONVEYOR_REVIEWER=0

HOOK="$(cd "$(dirname "$0")/.." && pwd)/bash-guardrails.sh"
PASS=0 FAIL=0

# The file runs itself once per part, side by side, and prints the parts in
# order: a hook call costs about 0.2 s and there are some 900. Every
# line runs in every part, so each part has all fixtures and helpers; outside
# its own part a run has `true` for the hook and check records nothing.
# One part alone: GUARDRAILS_TEST_PART=<n> in front. Split into parts:
# of four, two ran 77 and 79 s side by side while the shortest ran 34 s. Of
# five, the fifth held 67 s of the 115 s of hook calls and the fourth 6 s, so the
# file took as long as its fifth part: it is cut in four (parts 5 to 8) at the
# measured times (2026-11-12). Move a `part` line when a part grows.
#
# A case filter: CONVEYOR_SHELL_TEST_CASE=<text>[,<text>] runs only the top-level checks whose text
# holds one of the texts; lib/case-filter.sh says how. A part with no selected check prints `0 passed, 0 failed`
# and is accepted; each text must select a check in some part.
. "$(dirname "${BASH_SOURCE[0]}")/lib/case-filter.sh"
PARTS=8
if [ -z "${GUARDRAILS_TEST_PART:-}" ]; then
  cf_refuse_empty
  OUT=$(mktemp -d); trap 'rm -rf "$OUT"' EXIT; : > "$OUT/hits"
  for P in $(seq "$PARTS"); do GUARDRAILS_TEST_PART=$P GUARDRAILS_TEST_HITS=$OUT/hits bash "$0" > "$OUT/$P" 2>&1 & done
  wait
  for P in $(seq "$PARTS"); do
    # A part that died before its count, or ran no case, is a failure, never a shorter list. Under a selector a
    # part may select nothing.
    if [[ $(tail -1 "$OUT/$P") =~ ^([0-9]+)\ passed,\ ([0-9]+)\ failed$ ]] \
      && { grep -qE '^(ok  |FAIL) ' "$OUT/$P" || { [ -n "${CONVEYOR_SHELL_TEST_CASE+x}" ] && [ "${BASH_REMATCH[1]}${BASH_REMATCH[2]}" = 00 ]; }; }; then
      PASS=$((PASS+BASH_REMATCH[1])) FAIL=$((FAIL+BASH_REMATCH[2]))
      sed '$d' "$OUT/$P" | sed '${/^$/d;}'
    else
      cat "$OUT/$P"; echo "FAIL part $P of $PARTS did not finish"; FAIL=$((FAIL+1))
    fi
  done
  echo
  echo "$PASS passed, $FAIL failed"
  # Each text must run a check of its own: one matching text would otherwise hide a misspelled one.
  [ -z "${CONVEYOR_SHELL_TEST_CASE+x}" ] || cf_missed "$OUT/hits" || exit 2
  [ "$FAIL" -eq 0 ]; exit
fi
case "$GUARDRAILS_TEST_PART" in [1-$PARTS]) ;; *) echo "FAIL no such part: $GUARDRAILS_TEST_PART (parts: 1 to $PARTS)" >&2; exit 2 ;; esac
# Each part records the texts that select a check in it, so the parent can name a text that ran nothing.
[ -z "${CONVEYOR_SHELL_TEST_CASE+x}" ] || cf_install "${GUARDRAILS_TEST_HITS:-}"
REAL_HOOK=$HOOK
part() { if [ "$1" = "$GUARDRAILS_TEST_PART" ]; then ON=1 HOOK=$REAL_HOOK; else ON=0 HOOK=true; fi; }
part 1

# Every default case runs from a disposable repository, so a run from a card's
# worktree reads the same checkout shape as a run from main's.
MAIN_TMP=$(mktemp -d)
git -C "$MAIN_TMP" init -q
printf '{}\n' > "$MAIN_TMP/package.json"
trap 'rm -rf "$MAIN_TMP"' EXIT

run_hook() { ( cd "$MAIN_TMP" && echo "$1" | "$HOOK" >/dev/null 2>&1; echo $? ); }
check() { [ "$ON" = 1 ] || return 0; if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected $2, got $3)"; fi }
# Outside its own part a run builds no payload: the parts each paid a jq per case for nothing.
json() { [ "$ON" = 1 ] || return 0; jq -cn --arg cmd "$1" '{tool_input:{command:$cmd}}'; }
# A refusal these guards keep must hand back a concrete command. Take its
# `Try:` line and replay it in the same seat: it has to pass, or the advice is
# a placeholder or something another guard blocks.
check_try() { # label, command, [seat dir]
  local DIR=${3:-$MAIN_TMP} OUT TRY
  OUT=$(cd "$DIR" && json "$2" | "$HOOK" 2>&1 >/dev/null; echo "rc=$?")
  check "$1" 2 "${OUT##*rc=}"
  TRY=$(printf '%s\n' "$OUT" | sed -n 's/^Try: //p' | head -1)
  check "$1: the refusal names a Try: command" 1 "$([ -n "$TRY" ] && echo 1 || echo 0)"
  check "$1: its Try: command passes" 0 "$(cd "$DIR" && json "$TRY" | "$HOOK" >/dev/null 2>&1; echo $?)"
}

# A guard retired or turned into a rewrite: the call runs, as written or rewritten.
check_ok() { # label, command
  check "$1" 0 "$(run_hook "$(json "$2")")"
}

# --- heap cap on node's test runner (.claude/rules/tests.md, Heap cap) -------
check "bare node --test blocks" 2 \
  "$(run_hook "$(json 'node --test src/x.test.ts')")"
check "node --require ts-node/register --test blocks" 2 \
  "$(run_hook "$(json 'node --require ts-node/register --test src/x.test.ts')")"
check "cap ABOVE 4096 still blocks" 2 \
  "$(run_hook "$(json 'node --max-old-space-size=8192 --test src/x.test.ts')")"
check "npx tsx --test blocks" 2 \
  "$(run_hook "$(json 'npx tsx --test src/x.test.ts')")"
check "node --test after a && still blocks" 2 \
  "$(run_hook "$(json 'npm run build && node --test src/x.test.ts')")"

# Short npm scripts here: in main's pane the suites themselves are long jobs, refused by the long-job block below.
check "npm run test:files passes (script carries the cap)" 0 \
  "$(run_hook "$(json 'npm run test:files a.test.ts')")"
check "npm run test:changed passes" 0 \
  "$(run_hook "$(json 'npm run test:changed')")"
check "capped node --test passes" 0 \
  "$(run_hook "$(json 'node --max-old-space-size=4096 --test src/x.test.ts')")"
check "capped node --test with ts-node passes" 0 \
  "$(run_hook "$(json 'node --max-old-space-size=4096 --test --require ts-node/register src/x.test.ts')")"
check "a lower cap passes" 0 \
  "$(run_hook "$(json 'node --max-old-space-size=2048 --test src/x.test.ts')")"
check "ordinary node script passes" 0 \
  "$(run_hook "$(json 'node scripts/thing.js')")"
check "companion --test-concurrency flag alone is not the runner switch" 0 \
  "$(run_hook "$(json 'node --test-concurrency=4 scripts/thing.js')")"

# --- per-segment cap: one segment's flag must not vouch for another ---------
check "capped segment does not vouch for an uncapped one" 2 \
  "$(run_hook "$(json 'node --max-old-space-size=4096 --test a.test.ts && node --test b.test.ts')")"
check "uncapped segment after a semicolon blocks" 2 \
  "$(run_hook "$(json 'node --max-old-space-size=4096 --test a.test.ts; node --test b.test.ts')")"
check "both segments capped passes" 0 \
  "$(run_hook "$(json 'node --max-old-space-size=4096 --test a.test.ts && node --max-old-space-size=4096 --test b.test.ts')")"
check "npm segment is skipped, node args and all" 0 \
  "$(run_hook "$(json 'npm run test:files -- node --test x.test.ts')")"
check "a single & is a segment boundary too" 2 \
  "$(run_hook "$(json 'node --max-old-space-size=4096 --test a.test.ts & node --test b.test.ts')")"
check "a larger flag after the cap blocks" 2 \
  "$(run_hook "$(json 'node --max-old-space-size=4096 --max-old-space-size=8192 --test x.test.ts')")"
# No heap flag above the cap, in either spelling, wherever it sits. The
# guard used to read the hyphen spelling only and trust the last one, so the
# underscore spelling after the cap ran node at 8 GB. Which flag node honours is
# no longer the guard's question: a larger one has no reason to be there.
check "a larger flag before the cap blocks too" 2 \
  "$(run_hook "$(json 'node --max-old-space-size=8192 --max-old-space-size=4096 --test x.test.ts')")"
check "the underscore spelling after the cap blocks" 2 \
  "$(run_hook "$(json 'node --max-old-space-size=4096 --max_old_space_size=8192 --test x.test.ts')")"
check "the underscore spelling after the runner switch blocks" 2 \
  "$(run_hook "$(json 'node --max-old-space-size=4096 --test x.test.ts --max_old_space_size=8192')")"
check "a mixed spelling blocks" 2 \
  "$(run_hook "$(json 'node --max-old-space-size=4096 --max_old-space_size=8192 --test x.test.ts')")"
check "a larger flag written with a space blocks" 2 \
  "$(run_hook "$(json 'node --max-old-space-size=4096 --max-old-space-size 8192 --test x.test.ts')")"
check "a larger flag in NODE_OPTIONS beside the cap blocks" 2 \
  "$(run_hook "$(json 'NODE_OPTIONS=--max_old_space_size=8192 node --max-old-space-size=4096 --test x.test.ts')")"
check "the underscore spelling alone, above the cap, blocks" 2 \
  "$(run_hook "$(json 'node --max_old_space_size=8192 --test x.test.ts')")"
check "the underscore spelling at the cap is the cap" 0 \
  "$(run_hook "$(json 'node --max_old_space_size=4096 --test x.test.ts')")"
check "the cap in NODE_OPTIONS still passes" 0 \
  "$(run_hook "$(json 'NODE_OPTIONS=--max-old-space-size=4096 node --test x.test.ts')")"
check "the cap twice, one in each spelling, passes" 0 \
  "$(run_hook "$(json 'NODE_OPTIONS=--max-old-space-size=4096 node --max_old_space_size=2048 --test x.test.ts')")"
# The same miss as git-safety.sh's quoted subcommand: a quoted word is still the word node gets.
check "a quoted runner switch is still the runner" 2 \
  "$(run_hook "$(json 'node "--test" x.test.ts')")"
check "a quoted node is still node" 2 \
  "$(run_hook "$(json '"node" --test x.test.ts')")"
check "a quoted larger flag beside the cap blocks" 2 \
  "$(run_hook "$(json 'node --max-old-space-size=4096 "--max_old_space_size=8192" --test x.test.ts')")"
check "a quoted cap is the cap" 0 \
  "$(run_hook "$(json 'node "--max-old-space-size=4096" --test x.test.ts')")"
check "a quoted cap in NODE_OPTIONS is the cap" 0 \
  "$(run_hook "$(json 'NODE_OPTIONS="--max-old-space-size=4096" node --test x.test.ts')")"
check "a larger flag in another segment does not block a capped run" 0 \
  "$(run_hook "$(json 'node --max-old-space-size=8192 build.js && node --max-old-space-size=4096 --test x.test.ts')")"

# --- prefixes and quoting: what is not actually a node invocation ------------
check "VAR=value before npm still reads as npm" 0 \
  "$(run_hook "$(json 'CI=1 npm run test:files -- node --test x.test.ts')")"
check "env before npm still reads as npm" 0 \
  "$(run_hook "$(json 'env CI=1 npm run test:files -- node --test x.test.ts')")"
check "a VAR=value prefix does NOT excuse a real node --test" 2 \
  "$(run_hook "$(json 'CI=1 node --test x.test.ts')")"
check "the pattern inside single quotes is a search, not a command" 0 \
  "$(run_hook "$(json "rg 'node --test src/x.test.ts' .claude")")"
check "the pattern inside double quotes passes too" 0 \
  "$(run_hook "$(json 'grep -rn "node --test" docs/')")"
check "a real invocation BESIDE a quoted mention still blocks" 2 \
  "$(run_hook "$(json "rg 'node --test' .claude && node --test x.test.ts")")"
# The strip ran line by line, so a quote or heredoc spanning lines kept
# its prose and a commit message naming the runner blocked.
check "a heredoc commit message naming node --test passes" 0 \
  "$(run_hook "$(json $'git commit -m "$(cat <<\'EOF\'\nfix: the suite ran node --test without a cap\nEOF\n)"')")"
check "a two-line quoted message naming node --test passes" 0 \
  "$(run_hook "$(json $'git commit -m "first\nnode --test x.test.ts"')")"
check "a real node --test after a heredoc still blocks" 2 \
  "$(run_hook "$(json $'cat <<EOF\nnode --test prose\nEOF\nnode --test x.test.ts')")"
check "an empty quote inside --test does not dodge the prefilter" 2 \
  "$(run_hook "$(json "node --te''st x.test.ts")")"
check "the heap check prints no grep warning" "" \
  "$(cd "$MAIN_TMP" && json 'node --max-old-space-size=4096 --test x.test.ts' | "$HOOK" 2>&1 >/dev/null)"

# --- the tool-steering rules are gone ---------------------------------------
# The hook told Claude to use Read instead of cat and Glob instead of find.
# That cost a fork on every Bash call to restate a preference no incident
# traces to, and Codex has neither tool, so the rule already carried an
# AGENT_KIND branch to switch itself off for half its callers.
READ_TMP=$(mktemp -d)
printf 'one line\n' >"$READ_TMP/small.md"
head -c 40000 /dev/zero | tr '\0' 'x' >"$READ_TMP/big.md"

check "cat for reading passes" 0 \
  "$(run_hook "$(json "cat $READ_TMP/small.md")")"
check "head for reading passes" 0 \
  "$(run_hook "$(json 'head -20 package.json')")"
check "cat for reading is SILENT" "" \
  "$(cd "$MAIN_TMP" && echo "$(json "cat $READ_TMP/small.md")" | "$HOOK" 2>&1)"
check "find for discovery passes" 0 \
  "$(run_hook "$(json 'find src -name "*.ts"')")"
check "find for discovery is SILENT" "" \
  "$(cd "$MAIN_TMP" && echo "$(json 'find src -name "*.ts"')" | "$HOOK" 2>&1)"

# --- the read cap is gone -----------
# 2,940 guard blocks in 7 days, nearly all worked around: a read of any size
# passes. The heap cap and the pathless-search block stay (cases below).
for C in "cat $READ_TMP/big.md" "nl -ba $READ_TMP/big.md" "sed -n '1,400p' $READ_TMP/big.md" \
  "head -400 $READ_TMP/big.md" "tail -n 400 $READ_TMP/big.md" "git log --oneline | head -n 151"; do
  check "a read over the old 150-line cap passes: $C" 0 "$(run_hook "$(json "$C")")"
done
check "a large read is SILENT" "" \
  "$(cd "$MAIN_TMP" && json "sed -n '1,400p' $READ_TMP/big.md" | "$HOOK" 2>&1)"
check "a large read beside a pathless search still blocks" 2 \
  "$(run_hook "$(json "cat $READ_TMP/big.md; rg -n foo")")"
check "a large read beside an uncapped node --test still blocks" 2 \
  "$(run_hook "$(json "sed -n '1,400p' $READ_TMP/big.md && node --test x.test.ts")")"
# A note's text is data: a here-document that cat or tee reads, alone
# on its line, with nothing after its end word. Any other here-document is
# read as commands: a shell may be fed it, or a later line may run the file.
check "a note written by cat that names a pathless search passes" 0 \
  "$(run_hook "$(json "cat > /tmp/note.md <<'EOF'
rg -n foo
EOF")")"
check "a note appended by cat, tab-indented, that a command follows is read as a search; the computed path warns (G4)" 0 \
  "$(run_hook "$(json "cat >> /tmp/note.md <<-'EOF'
	rg foo \$X
	EOF
ls")")"
check "a note with no quoted end word that names a pathless search passes" 0 \
  "$(run_hook "$(json "cat > /tmp/note.md <<EOF
rg -n foo
EOF")")"
check "a note written by tee that names a pathless search passes" 0 \
  "$(run_hook "$(json "tee /tmp/note.md <<'EOF' >/dev/null
rg -n foo
EOF")")"
check "a pathless search after the note ends still blocks" 2 \
  "$(run_hook "$(json "cat > /tmp/note.md <<'EOF'
note
EOF
rg -n foo")")"
check "a pathless search after two notes still blocks" 2 \
  "$(run_hook "$(json "cat > /tmp/a.md <<'A'
rg x
A
cat > /tmp/b.md <<'B'
rg y
B
rg -n foo")")"
# Under an end word with no quote bash runs a substitution in the body.
for NOTE_CMD in "cat <<EOF
\$(
rg -n foo
)
EOF" "tee /tmp/n.md <<EOF
\$(
rg -n foo
)
EOF" "cat > /tmp/n.md <<-EOF
	\`
	rg -n foo
	\`
	EOF" "cat <<123
\$(
rg -n foo
)
123" "cat > /tmp/n.md <<EOF
x \${Y:-\$(
rg -n foo
)}
EOF"; do
  check "a pathless search a note with no quoted end word runs still blocks: $NOTE_CMD" 2 "$(run_hook "$(json "$NOTE_CMD")")"
done
check "the same substitution under a quoted end word runs nothing and passes" 0 \
  "$(run_hook "$(json "cat <<'EOF'
\$(
rg -n foo
)
EOF")")"
part 2
# The search rule looks inside `$( )` and backticks. One case per row of
# the issue's table and of the batch F probe table.
g() { check "substitution $1" "$2" "$(run_hook "$(json "$3")")"; }
g "issue row 1: a pathless search in an assignment's substitution is refused" 2 'X=$(rg -n foo)'
g "issue row 2: a pathless search on a line of an unquoted note is refused" 2 'cat <<EOF
$(rg -n foo)
EOF'
g "issue row 3: a note with a dated line that names a search passes" 0 'cat > /tmp/note.md <<EOF
Recorded at $(date)
rg -n foo
EOF'
g "a pathless search in a substitution used as an argument is refused" 2 'echo $(rg -n foo)'
g "a pathless search in a substitution that is the whole command is refused" 2 '$(rg -n foo)'
g "a pathless search in a substitution inside a double-quoted string is refused" 2 'echo "hits: $(rg -n foo)"'
g "a pathless search in backticks is refused" 2 'X=`rg -n foo`'
g "a pathless search in backticks inside a double-quoted string is refused" 2 'echo "hits: `rg -n foo`"'
g "a pathless search in backticks inside an unquoted note is refused" 2 'cat <<EOF
`rg -n foo`
EOF'
g "a pathless search in a substitution mid-line in an unquoted note is refused" 2 'cat > /tmp/n.md <<EOF
hits: $(rg -n foo) end
EOF'
g "an unquoted note that names a search mid-line passes" 0 'cat > /tmp/n.md <<EOF
run rg -n foo to look
EOF'
g "an apostrophe in an unquoted note does not hide a search after it" 2 "cat > /tmp/n.md <<EOF
it's a note
EOF
rg -n foo"
g "an apostrophe in a quoted note does not hide a search after it" 2 "cat > /tmp/n.md <<'EOF'
it's a note
EOF
rg -n foo"
g "an apostrophe in an unquoted note does not hide a substitution after it" 2 "cat > /tmp/n.md <<EOF
it's \$(rg -n foo)
EOF
ls"
g "a bounded search in a substitution passes" 0 'X=$(rg -n foo src)'
g "plain substitutions pass" 0 'echo $(date) $(git rev-parse HEAD) `whoami`'
g "a quoted note with plain text passes" 0 "cat > /tmp/n.md <<'EOF'
a note
EOF"
g "a substitution spelled inside single quotes passes" 0 "echo '\$(rg -n foo)' '\`rg -n foo\`'"
g "an escaped substitution passes" 0 'echo \$(rg -n foo) "\$(rg -n foo)"'
g "an escaped substitution in an unquoted note passes" 0 'cat > /tmp/n.md <<EOF
write \$(rg -n foo) and \`rg -n foo\`
EOF'
# One level of nesting, each form inside another.
g "a substitution in a double-quoted string in a substitution is refused" 2 'X=$(echo "a $(rg -n foo)")'
g "backticks in a substitution are refused" 2 'X=$(echo `rg -n foo`)'
g "a substitution in a substitution in an unquoted note is refused" 2 'cat <<EOF
$(echo "$(rg -n foo)")
EOF'
g "a substitution in a default value is refused" 2 'echo "${Y:-$(rg -n foo)}"'
g "a search over the checkout root in a substitution is refused" 2 'X=$(rg -n foo .)'
g "a recursive grep with no path in a substitution is refused" 2 'X=$(grep -rn foo)'
g "a grep of one file in a substitution passes" 0 'X=$(grep -n foo /tmp/x.log)'
# The substitution is judged as its own command line, where it stands.
g "a bounded search piped on inside a substitution passes" 0 'N=$(rg -c foo src | wc -l)'
g "a search reading a pipe inside a substitution passes" 0 'N=$(cat /tmp/x.log | rg foo)'
g "a search reading a pipe beside a substitution passes" 0 'echo "$(date)" | rg foo'
g "a search with its pattern from a substitution and a bounded path passes" 0 'rg -n -e "$(cat /tmp/pat)" src'
g "a search with its pattern from a substitution and no path is refused" 2 'rg -n -e "$(cat /tmp/pat)"'
g "a path in a variable the command sets is followed into a substitution" 0 'D=src; X=$(rg -n foo "$D")'
g "a cd before a substitution is followed" 0 "cd $READ_TMP && X=\$(rg -n foo .)"
g "a cd after a substitution does not bound it" 2 "X=\$(rg -n foo .); cd $READ_TMP"
# A substitution runs in its own shell: its cd and its assignments end with it.
g "a cd inside a substitution does not bound a search after it" 2 "X=\$(cd $READ_TMP); rg -n foo ."
g "a cd inside backticks does not bound a search after it" 2 "X=\`cd $READ_TMP\`; rg -n foo ."
g "a cd inside a quoted substitution does not bound a search after it" 2 "echo \"\$(cd $READ_TMP && rg -n foo .)\"; rg -n foo ."
g "an assignment inside a substitution does not rename a path after it" 2 'D=.; X=$(D=src); rg -n foo "$D"'
g "a cd inside a substitution bounds the search inside it" 0 "X=\$(cd $READ_TMP && rg -n foo .)"
g "an assignment inside a substitution names the path inside it" 0 'X=$(D=src; rg -n foo "$D")'
g "a cd before a substitution still bounds the search after it" 0 "cd $READ_TMP && X=\$(rg -n foo .) && rg -n bar ."
# One level of nesting: the inner one runs after the outer one's own commands before it, in the outer one's shell.
g "a nested search is judged after the outer substitution's assignment" 2 'D=src; X=$(D=.; echo "$(rg -n foo "$D")")'
g "a nested search in backticks is judged after the outer assignment" 2 'D=src; X=$(D=.; echo `rg -n foo "$D"`)'
g "a nested search in a default value is judged after the outer assignment" 2 'D=src; X=$(D=.; echo "${Y:-$(rg -n foo "$D")}")'
g "a nested search is bounded by the outer substitution's assignment" 0 'D=.; X=$(D=src; echo "$(rg -n foo "$D")")'
g "a nested search is judged after the outer substitution's cd" 0 "X=\$(cd $READ_TMP; echo \"\$(rg -n foo .)\")"
g "a cd in a nested substitution ends with it, inside the outer one" 2 "X=\$(echo \"\$(cd $READ_TMP)\"; rg -n foo .)"
g "an assignment in a nested substitution ends with it, inside the outer one" 2 'X=$(D=.; echo "$(D=src)"; rg -n foo "$D")'
g "the outer substitution's cd ends with it after a nested one" 2 "X=\$(cd $READ_TMP; echo \"\$(date)\"); rg -n foo ."
g "a bounded nested search still passes" 0 'X=$(echo "$(rg -n foo src)")'
# Stated limit, pinned as today's behaviour: the shell does not move, the guard thinks it did.
g "stated limit: a cd inside a pipeline is still followed" 0 "cd $READ_TMP | true; rg -n foo ."
g "an apostrophe in a comment does not hide a substitution after it" 2 "echo hi # it's
X=\$(rg -n foo)"
g "a substitution after a \$'...' string with an escaped quote is refused" 2 "echo \$'it\\'s'; X=\$(rg -n foo)"
g "a substitution in a comment passes" 0 'echo hi # $(rg -n foo)'
g "plain arithmetic beside a substitution passes" 0 'echo $((1 + 2)) $((1<<2)) $(date)'
# The `)` that closes a subshell is not part of the path it stands against.
g "a root search in a subshell, the bracket against the path, is refused" 2 '(rg -n foo /)'
g "a home search in a subshell is refused" 2 '(grep -r foo ~)'
g "a search over the checkout root in a subshell is refused" 2 '(rg -n foo .)'
g "a parent search in a subshell inside a subshell is refused" 2 '( (rg -n foo ..))'
g "a \$HOME search in a subshell is refused" 2 '(rg -n foo $HOME)'
g "a root search after a cd in a subshell is refused" 2 "(cd $READ_TMP && rg -n foo /)"
g "a bounded search in a subshell passes" 0 '(rg -n foo .claude/hooks)'
g "a bounded search after a cd in a subshell passes" 0 "(cd $READ_TMP && rg -n foo .)"
g "point 3: a search after an arithmetic shift is still refused" 2 'echo $((1<<2))
rg -n foo'
g "point 4: a search after a quoted here-document opener is still refused" 2 'echo "x; cat <<EOF"
rg -n foo'
# What is not a note is read as commands, as before.
g "a note that a command follows is read as commands" 2 'cat > /tmp/note.md <<EOF
Recorded at $(date)
rg -n foo
EOF
ls'
g "a note with a harmless substitution that a command follows passes" 0 'cat > /tmp/note.md <<EOF
Recorded at $(date)
EOF
ls'
g "a here-document with a command after it on its line is read as commands" 2 'cat > /tmp/n.sh <<EOF && bash /tmp/n.sh
rg -n foo
EOF'
g "a here-document a substitution's cat prints is read as commands" 2 'eval "$(cat <<EOF
rg -n foo
EOF
)"'
g "a here-document fed to a shell with no quoted end word is read as commands" 2 'bash <<EOF
rg -n foo
EOF'
# A search after a note is judged, whatever the note's end word.
for NOTE_CMD in "cat <<'END NOTE'
note
END NOTE
rg -n foo" "cat > /tmp/n.md <<'END NOTE'
note
END NOTE
rg -n foo" "cat <<E'OF'
note
EOF
rg -n foo" "cat <<'E'OF
note
EOF
rg -n foo" "cat <<\"E\"\"OF\"
note
EOF
rg -n foo" "cat <<E\\OF
note
EOF
rg -n foo" "cat <<EOF2
note
EOF2
rg -n foo" "cat <<'EOF'
note
EOF
cat <<'EOF'
note
EOF
rg -n foo"; do
  check "a pathless search after a note still blocks: $NOTE_CMD" 2 "$(run_hook "$(json "$NOTE_CMD")")"
done
# A here-document's end word is one plain word or the command is refused: no
# rule then has to read an odd one. Refused whatever follows, with or without
# a command after the note, and for the search rule and the in-place write
# rule alike.
ODD_ENDS=("<<'END NOTE'" "<<E'OF'" "<<'E'OF" '<<"E""OF"' "<<E\\OF" "<<'END'\\ NOTE" '<<"E\"OF"' '<<$TAG' '<<EOF#x' '<<~EOF' '<<' '<<-' "<<''" '<<EOF<<"A B"')
for E in "${ODD_ENDS[@]}"; do
  check "an end word that is not plain is refused: $E" 2 "$(run_hook "$(json "cat $E
note")")"
  check "and so is a search after such a note: $E" 2 "$(run_hook "$(json "cat $E
It's a note
EOF
rg -n foo")")"
  check "and an in-place source write after such a note: $E" 2 "$(run_hook "$(json "cat $E
note
EOF
sed -i s/a/b/ src/index.ts")")"
done
END_REFUSAL=$(json "cat <<'END NOTE'
note
END NOTE" | (cd "$MAIN_TMP" && "$HOOK" 2>&1 >/dev/null))
check "the refusal is one line that names the end word it saw and a plain one to use" "1 1 1" \
  "$(wc -l <<<"$END_REFUSAL" | tr -d ' ') $(grep -c "<<'END NOTE'" <<<"$END_REFUSAL") $(grep -c 'such as EOF' <<<"$END_REFUSAL")"
for E in "<<EOF" "<<'EOF'" '<<"EOF"' "<<\\EOF" "<< EOF" "<<-EOF" "<<-'EOF'" "<<EOF2" "<<E_O.F-1" "<<EOF >/tmp/n.md" "<<EOF;"; do
  check "a plain end word passes: $E" 0 "$(run_hook "$(json "cat $E
note
EOF")")"
done
check "a here-string is not a here-document and passes" 0 "$(run_hook "$(json "cat <<<'a note'; cat <<< \"\$X\"")")"
check "a shift in arithmetic passes" 0 "$(run_hook "$(json 'echo $((1<<2)) $((A << 3))')")"
check "a shift by a bracketed amount passes" 0 "$(run_hook "$(json 'echo $((1 << (2 + 1))) $(( (A+1) << B ))')")"
# Only a `<<` that bash would read as an operator is judged: one inside quotes,
# a comment or a plain note's text opens nothing.
for C in "echo '<<'" "node -e \"console.log('<<EOF')\"" "echo \"use <<'END NOTE' never\"" "echo hi # <<'A B'" "cat <<'EOF'
never write <<'END NOTE' or <<E'OF'
EOF"; do
  check "a << that is only text passes: $C" 0 "$(run_hook "$(json "$C")")"
done
check "an odd end word beside a quoted << is still refused" 2 "$(run_hook "$(json "echo '<<EOF'; cat <<'END NOTE'
note
END NOTE")")"
check "an odd end word after arithmetic is still refused" 2 "$(run_hook "$(json "echo \$((1 << 2)); cat <<'END NOTE'
note
END NOTE")")"
# The reader does not know `$'...'`, where `\'` does not end the string; with
# one in the command every `<<` in the text is judged as written.
check "an odd end word after a \$'...' string with an escaped quote is still refused" 2 "$(run_hook "$(json "echo \$'a\\'b'; cat <<'END NOTE'
note
END NOTE")")"
check "a plain end word after a \$'...' string passes" 0 "$(run_hook "$(json "echo \$'a\\'b'; cat <<'EOF'
note
EOF")")"
# Nothing may sit above the check that lets a command leave the hook unread.
check "the end-word check comes before every exit but the empty-command one" 1 \
  "$(awk '/^\[ -z "\$CMD" \] && exit 0$/ { next } /end word is not plain/ { found = 1 } /exit 0/ && !seen { print (found ? 1 : 0); seen = 1 }' \
    "$REAL_HOOK")"
check "a note with a quote mark and nothing after it passes" 0 \
  "$(run_hook "$(json "cat <<'EOF' | tee /tmp/n.md
It's a note
EOF")")"
check "a pathless search in a note that a later line runs still blocks" 2 \
  "$(run_hook "$(json "cat > /tmp/n.sh <<'EOF'
rg -n foo
EOF
bash /tmp/n.sh")")"
check "a pathless search in a note that a later line sources still blocks" 2 \
  "$(run_hook "$(json "cat > /tmp/n.sh <<'EOF'
rg -n foo
EOF
. /tmp/n.sh")")"
check "a pathless search in a here-document fed to a shell still blocks" 2 \
  "$(run_hook "$(json "bash <<'EOF'
rg -n foo
EOF")")"
check "a pathless search in a here-document cat pipes into a shell still blocks" 2 \
  "$(run_hook "$(json "cat <<'EOF' | bash
rg -n foo
EOF")")"
check "a pathless search in a here-document a subshell's cat prints still blocks" 2 \
  "$(run_hook "$(json "(cat <<'EOF'
rg -n foo
EOF
) | bash")")"
part 3
rm -rf "$READ_TMP"
# The heap cap is agent-independent and stays that way.
check "a Codex payload still gets the heap cap" 2 \
  "$(AGENT_KIND=codex bash -c 'echo "$1" | "$0" >/dev/null 2>&1; echo $?' "$HOOK" "$(json 'node --test x.test.ts')")"

# --- repo-wide text search (.claude/rules/agents.md, Token efficiency) -------
# Catches: a Try line that names only `src`, so the whole-repo question gets a command that cannot answer it.
check "rg_try_names_the_roots" "rg -n -e 'foo' src web shared lambdas infra scripts .claude" \
  "$(cd "$MAIN_TMP" && json 'rg foo | head' | "$HOOK" 2>&1 >/dev/null | sed -n 's/^Try: //p' | head -1)"

# Catches: a refusal a command can correct that ends with no Try line, or one whose Try line the same hook refuses.
# One row per guard Try site: hook, refused command, seat (main or wt), run_in_background, a recorded earlier run.
# The hook is handed the text; nothing runs. The Try line is replayed to the same hook in the same seat.
guard_refusals_print_try() {
  [ "$ON" = 1 ] || return 0
  local HOOKS_DIR TRY_BOX ASK
  HOOKS_DIR=$(dirname "$REAL_HOOK"); TRY_BOX=$(mktemp -d)
  git -C "$TRY_BOX" init -q -b main; git -C "$TRY_BOX" -c user.name=t -c user.email=t@t -c core.hooksPath=/dev/null commit -q --allow-empty -m init
  git -C "$TRY_BOX" worktree add -q "$TRY_BOX-wt" >/dev/null 2>&1
  printf 'gen.json linguist-generated=true\n' > "$TRY_BOX/.gitattributes"; seq 1 300 > "$TRY_BOX/gen.json"
  try_payload() { # tool, text, dir, background
    if [ "$1" = Read ]; then jq -cn --arg f "$2" --arg d "$3" '{tool_name:"Read",tool_input:{file_path:$f},cwd:$d,session_id:"try-row"}'
    else jq -cn --arg c "$2" --arg d "$3" --argjson b "${4:-false}" '{tool_name:"Bash",tool_input:{command:$c,run_in_background:$b},cwd:$d,session_id:"try-row"}'; fi
  }
  try_row() { # hook file, refused text, seat, [background], [recorded]
    local H=$HOOKS_DIR/$1 DIR=$MAIN_TMP TOOL=Bash OUT TRY L="$1: $2"
    case "$3" in wt) DIR=$TRY_BOX-wt ;; box) DIR=$TRY_BOX ;; esac
    [ "$1" = generated-read-guard.sh ] && TOOL=Read
    [ "${5:-}" != recorded ] || (cd "$DIR" && try_payload Bash "$2" "$DIR" "${4:-false}" | CLAUDE_PROJECT_DIR=$DIR "$H" >/dev/null 2>&1
      try_payload Bash "$2" "$DIR" "${4:-false}" | CLAUDE_PROJECT_DIR=$DIR "$H" --record-complete >/dev/null 2>&1)
    OUT=$(cd "$DIR" && try_payload "$TOOL" "$2" "$DIR" "${4:-false}" | CLAUDE_PROJECT_DIR=$DIR "$H" 2>&1 >/dev/null; echo "rc=$?")
    TRY=$(printf '%s\n' "$OUT" | sed -n 's/^Try: //p' | head -1)
    check "guard_refusals_print_try: $L refuses" 2 "${OUT##*rc=}"
    check "guard_refusals_print_try: $L prints a Try:" 1 "$([ -n "$TRY" ] && echo 1 || echo 0)"
    check "guard_refusals_print_try: $L Try passes the same hook: $TRY" 0 \
      "$(cd "$DIR" && try_payload Bash "$TRY" "$DIR" "${4:-false}" | CLAUDE_PROJECT_DIR=$DIR "$H" >/dev/null 2>&1; echo $?)"
  }
  try_row bash-guardrails.sh 'rg foo | head' main
  try_row git-safety.sh 'git push -f origin HEAD' main
  try_row git-safety.sh 'git push --force origin HEAD' main
  try_row git-safety.sh 'git push -fu origin HEAD' main
  try_row git-safety.sh 'git push origin +HEAD' main
  try_row git-safety.sh 'git checkout -f main' main
  try_row git-safety.sh 'git gc --prune=now' main
  try_row suite-rerun-guard.sh 'npm test' main
  try_row suite-rerun-guard.sh 'npm run test:unit' box false recorded
  rm -rf "$TRY_BOX" "$TRY_BOX-wt"
}
guard_refusals_print_try

check_ok "rg with a bare pattern and no path is rewritten, not refused" \
  'rg foo'
check_ok "rg with a quoted pattern and no path is rewritten, not refused" \
  "rg -n 'foo bar'"
check_ok "rg over . is rewritten, not refused" \
  "rg -n 'foo' ."
check_ok "rg over the checkout root is rewritten, not refused" \
  "rg foo $HOME/repos/sample-project"
check_ok "grep -r over . is rewritten, not refused" \
  'grep -rn foo .'
check_try "rg piped into head still blocks" \
  "rg 'foo' | head"
check "rg with a directory passes" 0 \
  "$(run_hook "$(json "rg -n 'foo' src/services")")"
check "rg with a bare pattern and an existing directory passes" 0 \
  "$(run_hook "$(json 'rg foo .claude/scripts')")"
check "rg with a root file and no directory passes" 0 \
  "$(run_hook "$(json "rg 'foo' package.json")")"
check "rg with a quoted pattern and a nested path passes" 0 \
  "$(run_hook "$(json "rg -l 'foo' web/src/pages")")"
check "grep without -r passes" 0 \
  "$(run_hook "$(json 'grep foo package.json')")"
check "grep -r with a directory passes" 0 \
  "$(run_hook "$(json 'grep -rn foo src/routes')")"

# BOUNDED IS ANYTHING BELOW THE ROOT. About 20 of 55 refusals were real
# bounded searches: a top-level folder off the old allowlist, a glob, a path
# after the command's own cd. The root, its parents and a pathless search stay out.
mkdir -p "$MAIN_TMP/policy" && touch "$MAIN_TMP/tsconfig.json" "$MAIN_TMP/tsconfig.web.json"
LOG_TMP=$(mktemp -d) && touch "$LOG_TMP/file.log"
check "rg over a top-level folder off the old allowlist passes" 0 \
  "$(run_hook "$(json 'rg x policy')")"
check "rg over a glob of root files passes" 0 \
  "$(run_hook "$(json 'rg x tsconfig*.json')")"
check "rg over a bare wildcard inside a folder passes" 0 \
  "$(run_hook "$(json 'rg x policy/*')")"
check "rg over a file named relative to the command's own cd passes" 0 \
  "$(run_hook "$(json "cd $LOG_TMP && rg x file.log")")"
check_ok "rg x with no path is rewritten, not refused" 'rg x'
check_ok "rg x . from the root is rewritten, not refused" 'rg x .'
check_ok "rg x .. from the root is rewritten, not refused" 'rg x ..'
check_try "a bare * glob is the whole checkout and still blocks" 'rg x *'
check_try "rg . after a cd to the checkout's parent still blocks" "cd $MAIN_TMP/.. && rg x ."
# A FAILED cd DOES NOT MOVE THE SHELL, so it must not move the search base: with
# `;` the rg still runs in the checkout root. `&&` is judged the same way.
check_try "rg . after a failed cd into a missing child still blocks" "cd $MAIN_TMP/missing; rg needle ."
check_try "rg . after a failed cd with && blocks the same way" "cd $MAIN_TMP/missing && rg needle ."
check "a failed cd keeps the old base for a bounded file" 0 \
  "$(run_hook "$(json "cd $MAIN_TMP/missing; rg x package.json")")"
rm -rf "$LOG_TMP"
# A VARIABLE AFTER A FIXED PREFIX IS JUDGED AS A GLOB FROM THE `$` ON. 19 of 20
# unbounded refusals on 2026-09-27 named a log such as /tmp/conveyor/x-$n.log.
check "rg over an absolute log path holding a variable passes" 0 \
  "$(run_hook "$(json 'rg x /tmp/conveyor/x-$n.log')")"
check "rg over a relative folder holding a variable passes" 0 \
  "$(run_hook "$(json 'rg x policy/$f')")"
check_ok "rg over a bare variable passes with a warning (G4)" 'rg x $X'
check_try "rg over a variable right under / still blocks" 'rg x /$X'
check_try "rg over a variable at the checkout root still blocks" "rg x $MAIN_TMP/\$X"
check_try "rg over a variable in the checkout's parent still blocks" "rg x $MAIN_TMP/../\$X"
# A LOOP VARIABLE BOUND TO BOUNDED PATHS IS BOUNDED. Only a one-word
# for-list resolved, so `for f in a b; do rg x "$f"; done` was refused though
# every value it can take is a bounded path.
check "a for loop over two bounded paths lets rg \"\$f\" pass" 0 \
  "$(run_hook "$(json 'for f in policy package.json; do rg x "$f"; done')")"
check "a for loop over a bounded glob and a file lets rg \$f pass" 0 \
  "$(run_hook "$(json 'for f in policy/* package.json; do rg x $f; done')")"
check "a later reassignment of the loop variable does not undo the loop's binding" 0 \
  "$(run_hook "$(json 'for f in policy package.json; do rg x "$f"; done; f=package.json')")"
check_try "a for loop with the checkout root among its paths still blocks" 'for f in policy .; do rg x "$f"; done'
check_ok "a for loop whose list holds a variable passes with a warning (G4)" 'for f in policy $X; do rg x "$f"; done'
check_try "a bare pathless rg inside a for loop still blocks" 'for f in policy package.json; do rg x; done'
# A VARIABLE BOUND BY `read` IS A LIST OF PATHS FED IN, ONE AT A TIME:
# each `rg "$f"` searches one listed path, never a bare repo-wide search, so it
# passes. What feeds the list is not judged (a read fed the checkout root is the
# accepted residual). `D=$(...)` stays refused: its value is unknown.
check "a while-read loop lets rg \"\$f\" pass" 0 \
  "$(run_hook "$(json 'git diff --name-only | while IFS= read -r f; do rg -n x "$f"; done')")"
check "a plain read binding lets rg \${f} pass" 0 \
  "$(run_hook "$(json 'while read f; do rg x ${f}; done < /tmp/conveyor/list')")"
check "a read with an input redirect binds its variable too" 0 \
  "$(run_hook "$(json 'read -r f < /tmp/conveyor/list; rg x "$f"')")"
check_ok "a read binding does not bound another variable: the other one warns (G4)" 'while read -r f; do rg x "$g"; done < /tmp/conveyor/list'
check_try "a later literal reassignment replaces the read binding" 'read -r f < /tmp/conveyor/list; f=.; rg x "$f"'
check_ok "a command-substitution assignment passes with a warning (G4)" 'D=$(git rev-parse --show-toplevel); rg x "$D"'
check_try "a bare pathless rg inside a read loop still blocks" 'while read -r f; do rg x; done < /tmp/conveyor/list'

# THE REFUSAL NAMES THE WHOLE-REPO FORM. This is the most-fired rule in
# the repo, and 19 of 51 blocks were followed by another block of the same rule,
# because it said what was forbidden and never what to ask instead.
SEARCH_REFUSAL=$(cd "$MAIN_TMP" && json 'rg -n foo . | head' | "$HOOK" 2>&1 >/dev/null)
check "the unbounded refusal names serena find_symbol" 1 \
  "$(grep -q 'serena find_symbol'<<<"$SEARCH_REFUSAL" && echo 1 || echo 0)"
check "the unbounded refusal names the roots to search instead" 1 \
  "$(grep -q 'src web shared lambdas infra scripts .claude' <<<"$SEARCH_REFUSAL" && echo 1 || echo 0)"

# A SESSION'S OWN TRANSCRIPTS ARE SEARCHABLE. They live under
# ~/.claude/projects/<project>/, outside every checkout, and both home forms
# were refused as unbounded before the path was ever resolved.
check "rg under ~/.claude/projects passes" 0 \
  "$(run_hook "$(json 'rg -n foo ~/.claude/projects/-home-x')")"
check "rg under \$HOME/.claude/projects passes" 0 \
  "$(run_hook "$(json 'rg -n foo $HOME/.claude/projects/-home-x')")"
# The home directory itself still holds every checkout, so it stays refused.
check_try "rg over the home directory still blocks" \
  'rg -n foo ~'
check "git grep passes" 0 \
  "$(run_hook "$(json 'git grep -n foo')")"
check "grep as a filter passes" 0 \
  "$(run_hook "$(json 'npm run typecheck 2>&1 | grep -c error')")"

part 4
# The chain runner that a direct local-checks run was sent to is gone: the full checks run directly.
check "a direct local-checks run passes" 0 \
  "$(run_hook "$(json 'bash scripts/ci/local-checks.sh --full --reuse-unchanged')")"

# A linked worktree, where git-dir and git-common-dir differ: a real one rather than a stub, because the stub
# is the thing most likely to drift.
WORKER_TMP=$(mktemp -d)
git -C "$WORKER_TMP" init -q 2>/dev/null
git -C "$WORKER_TMP" -c user.email=t@t -c user.name=t commit -q --allow-empty -m x 2>/dev/null
git -C "$WORKER_TMP" worktree add -q "$WORKER_TMP/wt" -b wtb >/dev/null 2>&1
run_hook_in() { ( cd "$1" 2>/dev/null && echo "$2" | "$HOOK" >/dev/null 2>&1; echo $? ); }

# --- aws must name a profile in every seat: the default credentials may reach an account no agent may touch
# The hook reads AWS_PROFILE from its own environment, so each case pins it.
aws_hook() { # <AWS_PROFILE value or "" for unset> <command> [seat dir]
  ( cd "${3:-$MAIN_TMP}" && json "$2" | if [ -n "$1" ]; then AWS_PROFILE=$1 "$HOOK"; else env -u AWS_PROFILE "$HOOK"; fi >/dev/null 2>&1; echo $? )
}
SAVED_AWS_PROFILE=${AWS_PROFILE-}; unset AWS_PROFILE
check_try "aws with no profile and none in the environment blocks" 'aws sts get-caller-identity'
check_try "aws with an empty --profile= blocks" 'aws s3 ls --profile='
check_try "aws whose AWS_PROFILE prefix is empty blocks" "AWS_PROFILE='' aws s3 ls"
[ -z "$SAVED_AWS_PROFILE" ] || export AWS_PROFILE=$SAVED_AWS_PROFILE
check "aws in a worker worktree with no profile blocks too" 2 "$(aws_hook '' 'aws s3 ls' "$WORKER_TMP/wt")"
check "aws --profile X passes" 0 "$(aws_hook '' 'aws --profile sample-dev sts get-caller-identity')"
check "aws --profile=X after the subcommand passes" 0 "$(aws_hook '' 'aws s3 ls --profile=sample-dev')"
check "an AWS_PROFILE=X prefix passes" 0 "$(aws_hook '' 'AWS_PROFILE=sample-dev aws s3 ls')"
check "an exported AWS_PROFILE before aws passes" 0 "$(aws_hook '' 'export AWS_PROFILE=sample-dev && aws s3 ls')"
check "aws with AWS_PROFILE in the environment passes" 0 "$(aws_hook sample-dev 'aws s3 ls')"
check "env -u AWS_PROFILE aws blocks even with AWS_PROFILE set" 2 "$(aws_hook sample-dev 'env -u AWS_PROFILE aws sts get-caller-identity')"
check "env -i aws blocks even with AWS_PROFILE set" 2 "$(aws_hook sample-dev 'env -i aws s3 ls')"
check "aws --version passes" 0 "$(aws_hook '' 'aws --version')"
check "aws later in a pipeline is still checked" 2 "$(aws_hook '' 'echo x | aws s3 cp - s3://b/k')"

rm -rf "$WORKER_TMP"

# The serena-down marker stands the symbols hint down. No session
# writes it, on an errored serena call; a worker that touches it by hand runs
# a whole cut with the gates off (2026-09-18).
check "touching the serena-down marker is refused" 2 \
  "$(run_hook "$(json 'touch /tmp/claude-serena-down-abc123')")"
check "writing the marker through a redirect is refused" 2 \
  "$(run_hook "$(json 'echo > "/tmp/claude-serena-down-$SID"')")"
check "an unrelated touch in /tmp passes" 0 \
  "$(run_hook "$(json 'touch /tmp/claude-other-marker')")"


# _implementer-tools.md said nothing of the bounded-path rule: one cut lost 10
# calls to those refusals (2026-09-18). The note names the path rule.
NOTE="$(dirname "$REAL_HOOK")/../briefs/_implementer-tools.md"
check "the tools note states the rg/grep rewrite and cap rule" 1 "$(grep -qE 'rg.*grep -r.*rewritten' "$NOTE" && echo 1 || echo 0)"

part 5
# --- in-place source writes from the shell --------------------------
# A shell edit skips every Edit/Write hook: the content tripwires, the audits,
# lint-fix and the main-edit guard. One builder made 19 of its edits that way
# on 2026-09-18.
check "sed -i on a source path is refused" 2 \
  "$(run_hook "$(json "sed -i 's/a/b/' src/x.ts")")"
check "perl -pi on a source path is refused" 2 \
  "$(run_hook "$(json "perl -pi -e 's/a/b/' shared/x.ts")")"
# A file copied over a source file skips the same hooks: a build applied its
# edits that way on 2026-10-13 and no content check saw them.
w() { check "copy over source: $1" "$2" "$(run_hook "$(json "$3")")"; }
w "cp onto a hook is refused" 2 'cp /tmp/x.sh .claude/hooks/git-safety.sh'
w "mv onto a hook is refused" 2 'mv /tmp/x.sh .claude/hooks/git-safety.sh'
w "tee onto a hook is refused" 2 'echo x | tee .claude/hooks/x.sh'
w "tee -a onto a source file is refused" 2 'tee -a src/a.ts < /tmp/x'
w "tee with a second operand in source is refused" 2 'echo x | tee /tmp/log src/a.ts'
w "cp -t into a source folder is refused" 2 'cp -t src /tmp/a.ts'
w "cp --target-directory= into a source folder is refused" 2 'cp --target-directory=src/services /tmp/a.ts'
w "cp of two files into a source folder is refused" 2 'cp /tmp/a.ts /tmp/b.ts src/services/'
w "install onto a hook is refused" 2 'install -m 755 /tmp/x.sh .claude/hooks/x.sh'
w "cp onto a hook with a redirect after it is refused" 2 'cp /tmp/x.sh .claude/hooks/x.sh 2>/dev/null'
w "cp onto a hook after another command is refused" 2 'cd /tmp/w && cp a.sh "$ROOT/.claude/hooks/a.sh"'
w "cp by its path onto a source file is refused" 2 '/bin/cp /tmp/a.ts web/src/a.ts'
check "the copy refusal names the target and points at Edit" 1 \
  "$(json 'cp /tmp/x.sh .claude/hooks/git-safety.sh' | "$HOOK" 2>&1 | grep -c 'git-safety.sh from the shell.*Edit')"
# The way to move a tracked file stays open, and the refusal names it.
w "git mv between two source paths passes" 0 'git mv src/a.ts src/b.ts'
check "the refusal of a mv names git mv" 1 \
  "$(json 'mv src/a.ts src/b.ts' | "$HOOK" 2>&1 | grep -c 'to rename or move a tracked file use git mv$')"
check "the refusal of a cp names git mv" 1 \
  "$(json 'cp /tmp/a.ts src/b.ts' | "$HOOK" 2>&1 | grep -c 'to rename or move a tracked file use git mv$')"
check "the refusal of a tee does not" 0 \
  "$(json 'echo x | tee src/b.ts' | "$HOOK" 2>&1 | grep -c 'git mv')"
w "cp between scratch files passes" 0 'cp /tmp/a.txt /tmp/b.txt'
w "cp of a source file out to scratch passes" 0 'cp src/a.ts /tmp/a.ts'
w "cp -r of a source folder out to scratch passes" 0 'cp -r .claude/hooks /tmp/hooks-copy'
w "cp between brief files passes" 0 'cp .claude/briefs/a.md .claude/briefs/b.md'
w "cp of a doc passes" 0 'cp docs/a.md docs/b.md'
w "cp into a folder made by mktemp passes" 0 'T=$(mktemp -d); cp src/a.ts "$T/src/a.ts"'
w "tee to a scratch log passes" 0 'npm run lint 2>&1 | tee /tmp/lint.log'
w "mv between scratch files passes" 0 'mv /tmp/a /tmp/b'
# Stated limits, pinned as today's behaviour.
w "stated limit: dd onto a source file is not followed" 0 'dd if=/tmp/x of=src/a.ts'
w "stated limit: a copy behind a wrapper is not followed" 0 'sudo cp /tmp/x src/a.ts'
# A scratch fixture outside every checkout is no source file, whatever its
# folders are called: the rule refused a fake ~/.claude tree under /tmp.
check "a write under /tmp passes though a folder there is named .claude" 0 \
  "$(run_hook "$(json "mkdir -p /tmp/uc2402/.claude/projects/-fixture-ws-u; echo '{}' > /tmp/uc2402/.claude/projects/-fixture-ws-u/s.jsonl")")"
check "a write under /private/tmp passes though a folder there is named src" 0 \
  "$(run_hook "$(json "echo x > /private/tmp/uc2402/src/a.ts")")"
check "sed -i under the system temp folder passes though a folder there is named scripts" 0 \
  "$(run_hook "$(json "sed -i 's/a/b/' /var/folders/lh/x/T/tmp.abc/scripts/a.sh")")"
check "a write under a folder the same command made with mktemp passes" 0 \
  "$(run_hook "$(json "T=\$(mktemp -d); mkdir -p \"\$T/.claude/projects/-fixture-ws-u\"; echo '{}' > \$T/.claude/projects/-fixture-ws-u/s.jsonl")")"
check "a quoted, braced write under a mktemp folder passes" 0 \
  "$(run_hook "$(json "T=\"\$(mktemp -d /tmp/x.XXXX)\" && echo x > \"\${T}/src/a.ts\"")")"
check "a write under a variable no mktemp set is refused when it names a source folder" 2 \
  "$(run_hook "$(json "T=\$(git rev-parse --show-toplevel); echo x > \$T/.claude/hooks/x.sh")")"
check "a write under a variable set twice, once by mktemp, is refused" 2 \
  "$(run_hook "$(json "T=\$(mktemp -d); T=.; echo x > \$T/.claude/hooks/x.sh")")"
check "a relative source write after a mktemp on the line is refused" 2 \
  "$(run_hook "$(json "T=\$(mktemp -d); echo x > .claude/hooks/x.sh")")"
check "a relative source write after a cd into /tmp is refused: it may be a checkout" 2 \
  "$(run_hook "$(json "cd /tmp/tb12d-head && sed -i.bak 's/a/b/' .claude/scripts/__tests__/builder.test.sh")")"
check "a /tmp path that climbs back out of /tmp is refused" 2 \
  "$(run_hook "$(json "echo x > /tmp/../opt/checkout/src/a.ts")")"
check "a python heredoc opening a source path for writing is refused" 2 \
  "$(run_hook "$(json "python3 - <<'EOF'
open('lambdas/x.py', 'w').write('x')
EOF")")"
check "a node -e writeFile on a source path is refused" 2 \
  "$(run_hook "$(json "node -e \"require('fs').writeFileSync('.claude/hooks/x.sh', 'x')\"")")"
check "a pathlib write_text on a source path is refused" 2 \
  "$(run_hook "$(json "python3 -c \"from pathlib import Path; Path('web/src/x.ts').write_text('x')\"")")"
check "a write through a variable naming a source path is refused" 2 \
  "$(run_hook "$(json "python3 - <<'EOF'
p = 'src/services/x.ts'
s = open(p).read()
open(p, 'w').write(s.replace('a', 'b'))
EOF")")"
check "the refusal points at Edit and serena" 1 \
  "$(cd "$MAIN_TMP" && json "sed -i 's/a/b/' src/x.ts" | "$HOOK" 2>&1 | grep -c 'Edit.*replace_content')"
check "a python write to the gitignored routing log passes" 0 \
  "$(run_hook "$(json "python3 -c \"open('.claude/routing-log', 'a').write('x')\"")")"
check "a python write to an approvals file passes" 0 \
  "$(run_hook "$(json "python3 -c \"open('.claude/approvals/red-tests-u-abc', 'w').write('x')\"")")"
check "a python write to another .claude file is still refused" 2 \
  "$(run_hook "$(json "python3 -c \"open('.claude/routing.json', 'w').write('x')\"")")"
check "sed -i under /tmp passes" 0 \
  "$(run_hook "$(json "sed -i 's/a/b/' /tmp/conveyor/x")")"
check "perl -pi under /tmp passes" 0 \
  "$(run_hook "$(json "perl -pi -e 's/a/b/' /tmp/conveyor/x")")"
check "a sed script naming /src/ on a /tmp file passes" 0 \
  "$(run_hook "$(json "sed -i 's|/src/|/dist/|g' /tmp/conveyor-config.txt")")"
check "a perl -e script naming /src/ on a /tmp file passes" 0 \
  "$(run_hook "$(json "perl -pi -e 's|/src/|/dist/|g' /tmp/conveyor-config.txt")")"
check "sed -i with an attached -e script is refused" 2 \
  "$(run_hook "$(json "sed -i -e's/a/b/' src/x.ts")")"
check "perl -pi with an attached -e script is refused" 2 \
  "$(run_hook "$(json "perl -pi -e's/a/b/' src/x.ts")")"
check "sed -i.bak with the script as first operand is refused" 2 \
  "$(run_hook "$(json "sed -i.bak 's/a/b/' src/x.ts")")"
check "sed -i -e with the source file after the script is refused" 2 \
  "$(run_hook "$(json "sed -i -e 's/a/b/' -e 's/c/d/' infra/x.ts")")"
check "a python write under /tmp passes" 0 \
  "$(run_hook "$(json "python3 - <<'EOF'
open('/tmp/conveyor/x', 'w').write('x')
EOF")")"
check "a node writeFile under /tmp passes" 0 \
  "$(run_hook "$(json "node -e \"require('fs').writeFileSync('/tmp/conveyor/x', 'x')\"")")"
check "a read-only python heredoc on a source path passes" 0 \
  "$(run_hook "$(json "python3 - <<'EOF'
print(open('src/x.ts').read().count('a'))
EOF")")"
check "reading source and writing /tmp in one python heredoc passes" 0 \
  "$(run_hook "$(json "python3 - <<'EOF'
s = open('src/x.ts').read()
open('/tmp/conveyor/out', 'w').write(s)
EOF")")"
check "a Path variable writing /tmp after reading source passes" 0 \
  "$(run_hook "$(json "python3 - <<'EOF'
from pathlib import Path
p = Path('/tmp/conveyor-out.txt')
s = Path('src/x.ts').read_text()
p.write_text(s)
EOF")")"
check "a Path variable naming a source path is refused" 2 \
  "$(run_hook "$(json "python3 - <<'EOF'
from pathlib import Path
p = Path('src/x.ts')
p.write_text(p.read_text().replace('a', 'b'))
EOF")")"
check "sed -n on a source path is a read and passes" 0 \
  "$(run_hook "$(json "sed -n '1,20p' src/x.ts")")"
# The shapes the first cut let through: the target reaches sed from find or a
# pipe, the write is a redirect, or the runner hides behind timeout/sudo.
check "find src -exec sed -i is refused" 2 \
  "$(run_hook "$(json "find src -name '*.ts' -exec sed -i 's/a/b/' {} +")")"
check "find /tmp -exec sed -i passes" 0 \
  "$(run_hook "$(json "find /tmp/conveyor/x -name '*.ts' -exec sed -i 's/a/b/' {} +")")"
check "rg -l src | xargs sed -i is refused" 2 \
  "$(run_hook "$(json "rg -l foo src | xargs -r sed -i 's/a/b/'")")"
check "rg -l /tmp | xargs sed -i passes" 0 \
  "$(run_hook "$(json "rg -l foo /tmp/conveyor/x | xargs -r sed -i 's/a/b/'")")"
check "an rg pattern that looks like a source path is not a target" 0 \
  "$(run_hook "$(json "rg -l 'src/foo' /tmp/conveyor/x | xargs -r sed -i 's/a/b/'")")"
check "grep -e names the pattern, so every operand is a path" 2 \
  "$(run_hook "$(json "grep -rl -e foo src | xargs sed -i 's/a/b/'")")"
check "grep -e's value is the pattern, not a target" 0 \
  "$(run_hook "$(json "grep -rl -e src/foo /tmp/conveyor/x | xargs sed -i 's/a/b/'")")"
# Every -e/-f names a pattern, not just the first (r1 sol-2).
check "a second -e value is a pattern too" 0 \
  "$(run_hook "$(json "rg -l -e foo -e src/bar /tmp/conveyor/x | xargs sed -i 's/a/b/'")")"
check "an attached -efoo names the pattern, so the operand is a path" 2 \
  "$(run_hook "$(json "grep -rl -efoo src | xargs sed -i 's/a/b/'")")"
check "a bundled -rle takes the next word as the pattern" 0 \
  "$(run_hook "$(json "grep -rle src/foo /tmp/conveyor/x | xargs sed -i 's/a/b/'")")"
check "--regexp=foo names the pattern, so the operand is a path" 2 \
  "$(run_hook "$(json "rg -l --regexp=foo src | xargs sed -i 's/a/b/'")")"
# `rg --files` lists files and takes no pattern, wherever the flag sits (r2 sol-1).
check "rg --files src | xargs sed -i is refused" 2 \
  "$(run_hook "$(json "rg --files src | xargs sed -i 's/a/b/'")")"
check "rg src --files | xargs sed -i is refused" 2 \
  "$(run_hook "$(json "rg src --files | xargs sed -i 's/a/b/'")")"
check "rg --files /tmp | xargs sed -i passes" 0 \
  "$(run_hook "$(json "rg --files /tmp/conveyor/x | xargs sed -i 's/a/b/'")")"
# With any -e, every operand is a path, even one written before the -e.
check "an operand before a later -e is a path" 2 \
  "$(run_hook "$(json "rg -l src -e foo | xargs sed -i 's/a/b/'")")"
# The search guard reads operands the same way. Refusing these two as "no path"
# was also what kept the two xargs cases above from reaching the write check.
check "rg src --files is a bounded listing" 0 "$(run_hook "$(json "rg src --files")")"
check "an operand before a later -e is a bounded search path" 0 "$(run_hook "$(json "rg -l src -e foo")")"
check "rg . --files is rewritten to the checkout root, capped (G4)" 0 "$(run_hook "$(json "rg . --files")")"

part 6
check "a redirect onto a source path is refused" 2 \
  "$(run_hook "$(json "echo x > src/x.ts")")"
check "an attached append redirect onto a source path is refused" 2 \
  "$(run_hook "$(json "echo x >>src/x.ts")")"
# `>|` is bash's clobber redirect, not a pipe (r1 sol-1).
check "a clobber redirect onto a source path is refused" 2 \
  "$(run_hook "$(json "echo x >|src/x.ts")")"
check "a spaced clobber redirect onto a source path is refused" 2 \
  "$(run_hook "$(json "echo x >| src/x.ts")")"
check "a clobber redirect under /tmp passes" 0 \
  "$(run_hook "$(json "echo x >|/tmp/conveyor/x")")"
check "an escaped > before a pipe is still a pipe" 0 \
  "$(run_hook "$(json "echo \\>|cat")")"
check "a redirect onto a quoted source path is refused" 2 \
  "$(run_hook "$(json "echo x > \"src/x.ts\"")")"
check "a quoted > is text, not a redirect" 0 \
  "$(run_hook "$(json "printf '%s\n' '>>src/x.ts' \"> src/y.ts\"")")"
check "an escaped > is text, not a redirect" 0 \
  "$(run_hook "$(json "printf '%s' \\>src/x.ts")")"
check "a > inside a multi-line quote is text, not a redirect" 0 \
  "$(run_hook "$(json "printf '%s' 'a
>src/x.ts'")")"
check "a redirect under /tmp passes" 0 \
  "$(run_hook "$(json "echo x > /tmp/conveyor/x 2>&1")")"
# Bash ends a word at an unquoted `>`: `foo>src/x` is `foo` plus a redirect.
check "a redirect attached to the end of a word onto a source path is refused" 2 \
  "$(run_hook "$(json "echo foo>src/x.ts")")"
check "the same attached redirect under /tmp passes" 0 \
  "$(run_hook "$(json "echo foo>/tmp/conveyor/x.ts")")"
check "an append attached to the end of a word onto a source path is refused" 2 \
  "$(run_hook "$(json "echo foo>>src/x.ts")")"
check "a > ending a word takes the next word as its target" 2 \
  "$(run_hook "$(json "echo foo> src/x.ts")")"
check "every redirect in one word is judged" 2 \
  "$(run_hook "$(json "echo a>/tmp/conveyor/x>src/x.ts")")"
check "a redirect after 2>&1 in the same word is judged" 2 \
  "$(run_hook "$(json "echo a 2>&1>src/x.ts")")"
check "2>&1 then a /tmp redirect in one word passes" 0 \
  "$(run_hook "$(json "echo a 2>&1>/tmp/conveyor/x.log")")"
check "a quoted > inside a word is text" 0 \
  "$(run_hook "$(json "echo \"foo>src/x.ts\"")")"
check "an escaped > inside a word is text" 0 \
  "$(run_hook "$(json "echo foo\\>src/x.ts")")"
check "an attached redirect does not hide the checkout root from the search guard" 2 \
  "$(run_hook "$(json "rg -n foo .>/tmp/conveyor/x.log")")"
check "a bounded search with an attached redirect passes" 0 \
  "$(run_hook "$(json "rg -n foo src>/tmp/conveyor/x.log")")"
check "a quoted => in a search pattern is not a redirect" 0 \
  "$(run_hook "$(json "rg -n 'foo =>' src")")"
# A backslash escapes only the next character, so `\\>` is a literal backslash
# and then a real redirect; `\\\>` is a backslash and then a literal `>`.
check "a redirect after an escaped backslash onto a source path is refused" 2 \
  "$(run_hook "$(json 'echo a\\>src/x.ts')")"
check "a redirect after an escaped backslash under /tmp passes" 0 \
  "$(run_hook "$(json 'echo a\\>/tmp/conveyor/x')")"
check "an escaped > after an escaped backslash is text" 0 \
  "$(run_hook "$(json 'echo a\\\>src/x.ts')")"
check "a clobber redirect after an escaped backslash is refused" 2 \
  "$(run_hook "$(json 'echo a\\>|src/x.ts')")"
check "an escaped quote opens no quoted span that could hide a redirect" 2 \
  "$(run_hook "$(json "echo \\'>src/x.ts\\'")")"
check "an escaped > does not glue a background & onto the next command" 2 \
  "$(run_hook "$(json 'echo \>& sed -i s/a/b/ src/x.ts')")"
check "a quoted \\> keeps its closing quote, so a later redirect is refused" 2 \
  "$(run_hook "$(json 'echo "\>" >src/x.ts')")"
check "a quoted \\> keeps its closing quote, so a later append is refused" 2 \
  "$(run_hook "$(json 'echo "\>" >>src/x.ts')")"
check "a heredoc body mentioning > src/x is text, not a redirect" 0 \
  "$(run_hook "$(json "cat > /tmp/conveyor/brief.md <<'EOF'
a redirect > src/x is refused
EOF")")"
check "a heredoc body quoting sed -i or xargs sed -i is text" 0 \
  "$(run_hook "$(json "cat > /tmp/conveyor/notes.md <<'EOF'
sed -i 's/a/b/' src/x.ts
grep -rl -e src/foo /tmp/x | xargs sed -i 's/a/b/'
EOF")")"
check "timeout N python3 writing source is refused" 2 \
  "$(run_hook "$(json "timeout 5 python3 -c \"open('src/x.ts', 'w').write('x')\"")")"
check "sudo -u x python3 writing source is refused" 2 \
  "$(run_hook "$(json "sudo -u x python3 -c \"open('src/x.ts', 'w').write('x')\"")")"
check "timeout N python3 writing /tmp passes" 0 \
  "$(run_hook "$(json "timeout 5 python3 -c \"open('/tmp/conveyor/x', 'w').write('x')\"")")"
# 553 edits went through inline Python, which skips every Edit check. The refusal above already covers
# the literal forms in every seat; two forms still passed: a move or copy ONTO a repo file, and a path variable whose
# assignment the parser cannot read (`f=pathlib.Path('src/a.ts')`), whose target was lost because the fallback list of
# quoted paths paired an outer `-c "..."` quote with an inner `'`.
for SEAT in run_hook; do
  check "inline_write_through_dotted_path_variable_refused ($SEAT)" 2 \
    "$($SEAT "$(json $'python3 -c "import pathlib; f=pathlib.Path(\'src/a.ts\'); f.write_text(\'x\')"')")"
  check "inline_move_or_copy_onto_repo_file_refused: shutil.copy ($SEAT)" 2 \
    "$($SEAT "$(json $'python3 -c "import shutil; shutil.copy(\'/tmp/x\',\'src/a.ts\')"')")"
  check "inline_move_or_copy_onto_repo_file_refused: os.replace ($SEAT)" 2 \
    "$($SEAT "$(json $'python3 -c "import os; os.replace(\'/tmp/x\',\'src/a.ts\')"')")"
  check "inline_move_or_copy_onto_repo_file_refused: shutil.move, a space after the comma ($SEAT)" 2 \
    "$($SEAT "$(json $'python3 -c "import shutil; shutil.move(\'/tmp/x\', \'.claude/hooks/x.sh\')"')")"
  check "inline_move_or_copy_onto_repo_file_refused: node renameSync ($SEAT)" 2 \
    "$($SEAT "$(json $'node -e "require(\'fs\').renameSync(\'/tmp/x\',\'src/a.ts\')"')")"
  check "inline_move_or_copy_onto_repo_file_refused: node copyFileSync ($SEAT)" 2 \
    "$($SEAT "$(json $'node -e "require(\'fs\').copyFileSync(\'/tmp/x\',\'src/a.ts\')"')")"
  check "a move onto a repo file through a variable the parser reads is refused ($SEAT)" 2 \
    "$($SEAT "$(json $'python3 -c "import os; d=\'src/a.ts\'; os.rename(\'/tmp/x\', d)"')")"
  # Pins: refused before and after.
  check "pin: a variable naming a source path then open(p, 'w') is refused ($SEAT)" 2 \
    "$($SEAT "$(json $'python3 -c "p=\'src/a.ts\'; open(p,\'w\').write(\'// eslint-disable-next-line\')"')")"
  # Pins: allowed before and after.
  check "pin: an inline write under /tmp passes ($SEAT)" 0 \
    "$($SEAT "$(json $'python3 -c "open(\'/tmp/x.txt\',\'w\').write(\'x\')"')")"
  check "pin: a copy FROM a repo file to /tmp passes ($SEAT)" 0 \
    "$($SEAT "$(json $'python3 -c "import shutil; shutil.copy(\'src/a.ts\',\'/tmp/x\')"')")"
  check "pin: a read-only inline script on a repo file passes ($SEAT)" 0 \
    "$($SEAT "$(json $'python3 -c "print(open(\'src/a.ts\').read())"')")"
  check "pin: a move between /tmp paths passes ($SEAT)" 0 \
    "$($SEAT "$(json $'node -e "require(\'fs\').renameSync(\'/tmp/x\',\'/tmp/y\')"')")"
  # A keyword argument names the target as plainly as a position does: `dst=` for a move or copy, `file=` for open.
  # Judged as anything else, it fell back to every quoted path and refused a repo-to-scratch copy for its SOURCE.
  check "keyword_destination_judged_as_written: copyfile from a repo file to dst='/tmp/x' passes ($SEAT)" 0 \
    "$($SEAT "$(json $'python3 -c "import shutil; shutil.copyfile(\'src/a.ts\', dst=\'/tmp/x\')"')")"
  check "keyword_destination_judged_as_written: copy from a repo file to dst='/tmp/x' passes ($SEAT)" 0 \
    "$($SEAT "$(json $'python3 -c "import shutil; shutil.copy(\'src/a.ts\', dst=\'/tmp/x\')"')")"
  check "keyword_destination_judged_as_written: src= then dst= to /tmp passes ($SEAT)" 0 \
    "$($SEAT "$(json $'python3 -c "import shutil; shutil.copy(src=\'src/a.ts\', dst=\'/tmp/x\')"')")"
  check "keyword_destination_judged_as_written: dst= before src= to /tmp passes ($SEAT)" 0 \
    "$($SEAT "$(json $'python3 -c "import shutil; shutil.copy(dst=\'/tmp/x\', src=\'src/a.ts\')"')")"
  check "keyword_destination_judged_as_written: open(file='/tmp/x', 'w') beside a repo read passes ($SEAT)" 0 \
    "$($SEAT "$(json $'python3 -c "s=open(\'src/a.ts\').read(); open(file=\'/tmp/x\', mode=\'w\').write(s)"')")"
  check "keyword_destination_judged_as_written: a copy to dst= a repo file is refused ($SEAT)" 2 \
    "$($SEAT "$(json $'python3 -c "import shutil; shutil.copy(\'/tmp/x\', dst=\'src/a.ts\')"')")"
  check "keyword_destination_judged_as_written: dst= a repo file before src= is refused ($SEAT)" 2 \
    "$($SEAT "$(json $'python3 -c "import os; os.replace(dst=\'src/a.ts\', src=\'/tmp/x\')"')")"
  check "keyword_destination_judged_as_written: open(file= a repo file, 'w') is refused ($SEAT)" 2 \
    "$($SEAT "$(json $'python3 -c "open(file=\'src/a.ts\', mode=\'w\').write(\'x\')"')")"
  # A Path(...) wrapper, bare or module-qualified, names its literal as plainly as a bare quote does. The extractor
  # stops at the wrapper's `)`, so an unnormalized `pathlib.Path('/tmp/x'` fell back to every quoted path and
  # refused a repo-to-scratch copy for its SOURCE.
  for P in Path pathlib.Path; do
    check "path_wrapped_destination_judged_as_written: copy to $P('/tmp/x') passes ($SEAT)" 0 \
      "$($SEAT "$(json "python3 -c \"import pathlib, shutil; shutil.copy('src/a.ts', $P('/tmp/x'))\"")")"
    check "path_wrapped_destination_judged_as_written: copy to dst=$P('/tmp/x') passes ($SEAT)" 0 \
      "$($SEAT "$(json "python3 -c \"import pathlib, shutil; shutil.copy('src/a.ts', dst=$P('/tmp/x'))\"")")"
    check "path_wrapped_destination_judged_as_written: copy to $P('src/a.ts') is refused ($SEAT)" 2 \
      "$($SEAT "$(json "python3 -c \"import pathlib, shutil; shutil.copy('/tmp/x', $P('src/a.ts'))\"")")"
    check "path_wrapped_destination_judged_as_written: copy to dst=$P('src/a.ts') is refused ($SEAT)" 2 \
      "$($SEAT "$(json "python3 -c \"import pathlib, shutil; shutil.copy('/tmp/x', dst=$P('src/a.ts'))\"")")"
    check "path_wrapped_destination_judged_as_written: $P('src/a.ts').write_text is refused ($SEAT)" 2 \
      "$($SEAT "$(json "python3 -c \"import pathlib; $P('src/a.ts').write_text('x')\"")")"
    check "path_wrapped_destination_judged_as_written: $P(p).write_text with p='/tmp/x' beside a repo read passes ($SEAT)" 0 \
      "$($SEAT "$(json "python3 -c \"import pathlib; p='/tmp/x'; $P(p).write_text(open('src/a.ts').read())\"")")"
    check "path_wrapped_destination_judged_as_written: $P(p).write_text with p='src/a.ts' is refused ($SEAT)" 2 \
      "$($SEAT "$(json "python3 -c \"import pathlib; p='src/a.ts'; $P(p).write_text('x')\"")")"
  done
done

part 7
# guard-python-copy-class: two NO-GOs were one class, a copy or move destination the
# parser could not read was judged by every quoted path, so the SOURCE refused a repo-to-scratch copy. A destination
# is now resolved only as a quoted literal, bare or in a Path wrapper, positional or dst=; every other form is
# refused with the plain cp/mv hint. The parser is not seat-keyed (cases above run both seats), so this runs one.
for FN in shutil.copy shutil.copy2 shutil.copyfile shutil.copytree shutil.move os.replace os.rename; do
  for P in "" Path pathlib.Path; do
    D=$P${P:+(}"'/tmp/x'"${P:+)} R=$P${P:+(}"'src/a.ts'"${P:+)}
    check "copy_destination_literal_resolved: $FN to $D from a repo file passes" 0 \
      "$(run_hook "$(json "python3 -c \"import os, shutil, pathlib; from pathlib import Path; $FN(Path('src/a.ts'), $D)\"")")"
    check "copy_destination_literal_resolved: $FN to dst=$D from src= a repo file passes" 0 \
      "$(run_hook "$(json "python3 -c \"import os, shutil, pathlib; from pathlib import Path; $FN(src='src/a.ts', dst=$D)\"")")"
    check "copy_destination_literal_resolved: $FN onto $R from a Path source is refused" 2 \
      "$(run_hook "$(json "python3 -c \"import os, shutil, pathlib; from pathlib import Path; $FN(Path('/tmp/y'), $R)\"")")"
    check "copy_destination_literal_resolved: $FN onto dst=$R from src= a Path source is refused" 2 \
      "$(run_hook "$(json "python3 -c \"import os, shutil, pathlib; from pathlib import Path; $FN(src=Path('/tmp/y'), dst=$R)\"")")"
  done
done

part 8
for FN in renameSync copyFileSync; do
  check "copy_destination_literal_resolved: node $FN to '/tmp/x' from a repo file passes" 0 \
    "$(run_hook "$(json "node -e \"require('fs').$FN(require('path').resolve('src/a.ts'), '/tmp/x')\"")")"
  check "copy_destination_literal_resolved: node $FN onto 'src/a.ts' from a computed source is refused" 2 \
    "$(run_hook "$(json "node -e \"require('fs').$FN(require('path').resolve('/tmp/y'), 'src/a.ts')\"")")"
done
check "copy_destination_literal_resolved: a variable assigned pathlib.Path('/tmp/x') passes" 0 \
  "$(run_hook "$(json "python3 -c \"import shutil, pathlib; d=pathlib.Path('/tmp/x'); shutil.copy('src/a.ts', d)\"")")"
for DST in "os.path.join('/tmp', 'x')" "f'/tmp/{n}'" "'/tmp/' + n" "Path('/tmp') / '../../src/a.ts'" "d" "pick('/tmp/x')"; do
  OUT=$( [ "$ON" = 1 ] && cd "$MAIN_TMP" && json "python3 -c \"import os, shutil; from pathlib import Path; n='x'; d='/tmp/' + n; shutil.copy('src/a.ts', $DST)\"" | "$HOOK" 2>&1 >/dev/null; echo "rc=$?")
  check "copy_destination_unreadable_refused_with_cp_hint: $DST" "rc=2 hint" \
    "$(grep -o 'rc=[0-9]*' <<<"$OUT")$(grep -q 'use plain cp or mv' <<<"$OUT" && echo ' hint')"
done
# A call whose arguments the parser cannot split hid its destination entirely: refused, not skipped.
for SCR in $'python3 -c "import shutil; from pathlib import Path; shutil.copy(Path(str(\'/tmp/y\')), \'src/a.ts\')"' \
  $'python3 - <<\'EOF\'\nimport shutil\nshutil.copy(\'/tmp/y\',\n  \'src/a.ts\')\nEOF'; do
  OUT=$( [ "$ON" = 1 ] && cd "$MAIN_TMP" && json "$SCR" | "$HOOK" 2>&1 >/dev/null; echo "rc=$?")
  check "copy_arguments_unreadable_refused_with_cp_hint: ${SCR:0:60}" "rc=2 hint" \
    "$(grep -o 'rc=[0-9]*' <<<"$OUT")$(grep -q 'use plain cp or mv' <<<"$OUT" && echo ' hint')"
done

# --- caller hunts go to serena's reference lookup -------------------
# 38 rg searches and no find_referencing_symbols call in one cut (2026-09-18).
# A HINT, NEVER A REFUSAL: 73% of refusals were retried unchanged, so the
# block cost a turn and redirected nothing. The search runs; the first caller
# hunt of a session carries the serena pointer as additionalContext.
HUNT_SID="guardrails-hunt-$$"
HUNT_HOME=$(mktemp -d)
printf '{"mcpServers":{"serena":{}}}\n' > "$HUNT_HOME/.claude.json"
trap 'rm -rf "$MAIN_TMP" "$HUNT_HOME" /tmp/claude-serena-tracker-$HUNT_SID* /tmp/claude-caller-hunt-$HUNT_SID* /tmp/claude-serena-down-$HUNT_SID*' EXIT
hunt() { # <session suffix> <command> -- prints hint, quiet, or rc=<n>
  local OUT RC
  OUT=$(cd "$MAIN_TMP" && jq -cn --arg cmd "$2" --arg sid "$HUNT_SID-$1" '{session_id:$sid,tool_input:{command:$cmd}}' | env -u CLAUDE_CONFIG_DIR HOME=$HUNT_HOME "$HOOK" 2>/dev/null); RC=$?
  [ "$RC" = 0 ] || { echo "rc=$RC"; return; }
  jq -e '.hookSpecificOutput.hookEventName == "PreToolUse" and (.hookSpecificOutput.additionalContext | contains("find_referencing_symbols"))' <<<"$OUT" >/dev/null 2>&1 && echo hint || echo quiet
}
check "a call-site hunt runs and carries the serena hint" hint "$(hunt a 'rg -n "analyzeRecapture\(" src')"
check "the identical retry runs with no second hint" quiet "$(hunt a 'rg -n "analyzeRecapture\(" src')"
check "another hunt in the same session is not hinted again" quiet "$(hunt a "rg -n 'ForgeryDetector\\b' lambdas")"
check "a snake_case config key search is not a hunt" quiet "$(hunt b 'rg -n "vt_capture_mode" src')"
check "a bounded PascalCase hunt is hinted" hint "$(hunt b "rg -n 'ForgeryDetector\\b' lambdas")"
check "a bounded camelCase hunt with grep -r is hinted" hint "$(hunt c "grep -rn '\\bforgeryDetector' shared")"
# A recorded lookup is one `refs:<name>` line per symbol in the session's tracker file.
printf 'refs:ForgeryDetector\nrefs:analyze\n' > "/tmp/claude-serena-tracker-$HUNT_SID-d"
check "after find_referencing_symbols named the symbol, no hint" quiet "$(hunt d "rg -n 'ForgeryDetector\\b' web/src")"
check "a quoted literal is a string search, no hint" quiet "$(hunt e "rg -n \"'analyzeRecapture('\" src")"
check "a caller hunt outside the source roots, no hint" quiet "$(hunt e 'rg -n "analyzeRecapture\(" docs')"
check "neither of those spent the session's one hint" hint "$(hunt e 'rg -n "analyzeRecapture\(" src')"
touch "/tmp/claude-serena-down-$HUNT_SID-f"
check "a serena error this session stands the hint down" quiet "$(hunt f 'rg -n "otherThing\(" src')"
check "a hinted hunt that another rule refuses still blocks" rc=2 "$(hunt g 'rg -n "otherThing\(" src; node --test x.test.ts')"
# A profile pane's .claude.json is CLAUDE_CONFIG_DIR/.claude.json; ~/.claude.json is not the file Claude Code reads there.
profile_hunt() { # <session suffix> <HOME .claude.json text> <profile .claude.json text> -> hint | quiet
  local H P OUT; H=$(mktemp -d); P=$(mktemp -d); printf '%s\n' "$2" > "$H/.claude.json"; printf '%s\n' "$3" > "$P/.claude.json"
  OUT=$(cd "$MAIN_TMP" && jq -cn --arg cmd 'rg -n "analyzeRecapture\(" src' --arg sid "$HUNT_SID-$1" '{session_id:$sid,tool_input:{command:$cmd}}' \
    | HOME=$H CLAUDE_CONFIG_DIR=$P "$HOOK" 2>/dev/null); rm -rf "$H" "$P"
  jq -e '.hookSpecificOutput.additionalContext | contains("find_referencing_symbols")' <<<"$OUT" >/dev/null 2>&1 && echo hint || echo quiet
}
check "serena configured only in the profile's .claude.json still gets the hint" hint "$(profile_hunt p1 '{}' '{"mcpServers":{"serena":{}}}')"
PROFILE_DISABLED=$(jq -cn --arg p "$(git -C "$MAIN_TMP" rev-parse --show-toplevel)" '{mcpServers:{serena:{}},projects:{($p):{disabledMcpServers:["serena"]}}}')
check "serena disabled for the repo in the profile's .claude.json stands the hint down" quiet \
  "$(profile_hunt p2 '{"mcpServers":{"serena":{}}}' "$PROFILE_DISABLED")"

# --- red-proof.sh, the approved red-before-green helper ---------------
# Builders hand-built scratch copies to show a test red and met 15 refusals; the helper breaks the line in its
# own scratch worktree, so its call is allowed even when the break it names reads like a source write. The
# test command it runs is still screened like any other.
check "red-proof.sh on a source line is allowed" 0 \
  "$(run_hook "$(json "bash .claude/scripts/red-proof.sh src/x.ts 12 'return 0;' -- npm run test:files -- src/__tests__/x.test.ts")")"
check "red-proof.sh whose replacement reads like a source write is allowed" 0 \
  "$(run_hook "$(json "bash .claude/scripts/red-proof.sh .claude/hooks/a.sh 3 'sed -i s/a/b/ src/x.ts > src/y.ts' -- bash t.sh")")"
check "red-proof.sh still refuses a bare node --test as its test" 2 \
  "$(run_hook "$(json "bash .claude/scripts/red-proof.sh src/x.ts 1 x -- node --test src/x.test.ts")")"

# --- the case filter -----------------------------------------------------------------------------
# The filter (lib/case-filter.sh) lets a fix round rerun the checks it names, not the 193 s file. Its variants run
# against fixtures/case-filter-fixture.sh, which sources the same filter: milliseconds, where a nested run of this
# file costs minutes. fx prints the fixture's exit status, its ok count and each text it named as unmatched.
if [ "$ON" = 1 ]; then
  CF_FIXTURE=$(dirname "${BASH_SOURCE[0]}")/fixtures/case-filter-fixture.sh
  # `chec[k]`: the filter takes a function whose body holds the word for a check, and would skip fx's call.
  fx() { # [selector] -- no argument runs the fixture with the selector unset
    local OUT; OUT=$(env -u CONVEYOR_SHELL_TEST_CASE ${1+CONVEYOR_SHELL_TEST_CASE="$1"} bash "$CF_FIXTURE" 2>&1)
    echo "$? $(grep -c '^ok   ' <<<"$OUT")$(sed -n "s/^FAIL no chec[k] matched the text '\(.*\)'$/ missed:\1/p" <<<"$OUT" | tr -d '\n')"
  }
  check "case_filter_runs_only_matching: unset runs every check" "0 4" "$(fx)"
  check "case_filter_runs_only_matching: a full group id runs that group's checks" "0 2" "$(fx 'group_a')"
  check "case_filter_runs_only_matching: a label substring runs that check alone" "0 1" "$(fx 'second check')"
  check "case_filter_runs_only_matching: a group id and a label together run both" "0 2" "$(fx 'group_b,second check')"
  check "case_filter_runs_only_matching: a wrapper row's text runs its nested check" "0 1" "$(fx 'fourth row')"
  check "case_filter_runs_only_matching: two texts matching the same check both count as matched" "0 1" \
    "$(fx 'group_a: first,first check')"
  check "case_filter_runs_only_matching: a misspelled text beside a matching one exits 2 and names the text" \
    "2 2 missed:grup_b" "$(fx 'group_a,grup_b')"
  check "case_filter_runs_only_matching: a selector matching nothing exits 2 with no ok line and names it" \
    "2 0 missed:no such label" "$(fx 'no such label')"
  check "case_filter_runs_only_matching: an empty selector exits 2" "2 0" "$(fx '')"
  check "case_filter_runs_only_matching: a selector of only a comma exits 2" "2 0" "$(fx ',')"
fi

# --- Rewrites and passes in place of refusals -------------------------------------------------------------------
# Bug caught: a shell append to a plan or doc skipped no Edit hook that matters for prose, yet was refused as a source write.
check "shell_append_to_md_passes" 0 "$(run_hook "$(json 'echo "- note" >> src/notes/plan.md')")"
check "shell_append_to_md_passes: a source file is still refused" 2 "$(run_hook "$(json 'echo "x" >> src/services/a.ts')")"
# Bug caught: the aws profile guard refused a profile that sat in a variable the command itself assigned.
check "aws_profile_in_variable_passes" 0 "$(aws_hook '' 'P="--profile sample-dev"; aws $P sts get-caller-identity')"
check "aws_var_without_profile_blocks" 2 "$(aws_hook '' 'P="--region us-east-1"; aws $P sts get-caller-identity')"
# Bug caught: a profile setting that never takes effect vouched for a call that ran on the default credentials, which
# may reach an account no agent may touch (passes 1-3): set after the call, on another command's prefix, under `false &&`, unset or
# emptied again, cleared before a repeated call, written as an argument, dropped by `env -i`, or a call inside `$(...)`,
# which was never checked at all; or a profile value the shell expands at run time, empty or not (pass 4). After the
# bar, the forms that do take effect still pass.
AWS_NEVER=('aws sts get-caller-identity $P; P=--profile=sample-dev' 'aws s3 ls; export AWS_PROFILE=sample-dev'
  'AWS_PROFILE=sample-dev true; aws s3 ls' 'P=--profile=sample-dev true; aws s3 ls $P'
  'false && P=--profile=sample-dev; aws s3 ls $P' 'export AWS_PROFILE=sample-dev; unset AWS_PROFILE; aws s3 ls'
  'export AWS_PROFILE=sample-dev; AWS_PROFILE=; aws s3 ls' 'P=--profile=sample-dev; aws s3 ls $P; P=; aws s3 ls $P'
  'aws s3 ls AWS_PROFILE=sample-dev' 'X=$(aws s3 ls)'
  'AWS_PROFILE="$UNSET_PROFILE" aws s3 ls' 'export AWS_PROFILE=sample-dev; AWS_PROFILE="$UNSET_PROFILE" aws s3 ls'
  "AWS_PROFILE='\$UNSET_PROFILE' aws s3 ls" 'aws --profile "$UNSET_PROFILE" s3 ls' 'aws --profile=$UNSET_PROFILE s3 ls'
  "P='--profile \$X'; aws s3 ls \$P" "export AWS_PROFILE='\$X'; aws s3 ls")
AWS_GOT=""; for C in "${AWS_NEVER[@]}"; do AWS_GOT+="$(aws_hook '' "$C") "; done
AWS_GOT+="$(aws_hook sample-dev 'unset AWS_PROFILE; aws s3 ls') $(aws_hook sample-dev 'AWS_PROFILE=; aws s3 ls') $(aws_hook sample-dev "AWS_PROFILE='' aws s3 ls") $(aws_hook '' 'export AWS_PROFILE=sample-dev; env -i aws s3 ls') $(aws_hook sample-dev 'aws --profile "$UNSET_PROFILE" s3 ls') $(aws_hook sample-dev "P='--profile \$X'; aws s3 ls \$P") |"
AWS_GOT+=" $(aws_hook '' 'P=--profile=sample-dev; aws s3 ls $P') $(aws_hook '' 'P="--profile sample-dev"; aws sts get-caller-identity $P') $(aws_hook '' 'X=1; export AWS_PROFILE=sample-dev && aws s3 ls') $(aws_hook sample-dev 'X=1; aws s3 ls') $(aws_hook sample-dev 'AWS_PROFILE=sample-dev; aws s3 ls') $(aws_hook '' 'aws --profile sample-dev s3 ls') $(aws_hook '' 'AWS_PROFILE="sample-dev" aws s3 ls')"
check "aws_profile_only_effective_vouches" "2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 | 0 0 0 0 0 0 0" "$AWS_GOT"

# A block that names no way forward costs a retry. Every BLOCKED message states what to run instead
# on a line of its own (`Instead:` or `Try:`) within the statement that prints it.
if [ "$ON" = 1 ]; then
  MISSING=$(awk '/BLOCKED/ && !/^[[:space:]]*#/ { if (n) print n; n = NR; ok = 0 }
    n && /(^|[^A-Za-z])(Instead|Try):/ { n = 0 }
    END { if (n) print n }' "$REAL_HOOK" | tr '\n' ' ')
  check "every BLOCKED message carries an Instead: or Try: line (unmatched at lines: ${MISSING:-none})" "" "$MISSING"
fi

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
