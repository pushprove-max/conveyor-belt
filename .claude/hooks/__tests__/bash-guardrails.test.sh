#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Self-test for bash-guardrails.sh. Run directly. This file has the heap cap, the reads and the notes, and the searches in substitutions; bash-guardrails-refusals.test.sh and bash-guardrails-writes.test.sh have the other cases.
set -u
export CONVEYOR_REVIEWER=0

HOOK="$(cd "$(dirname "$0")/.." && pwd)/bash-guardrails.sh"
PASS=0 FAIL=0

# The file runs itself once per part, side by side, and prints the parts in
# order: a hook call costs about 0.2 s. Every
# line runs in every part, so each part has all fixtures and helpers; outside
# its own part a run has `true` for the hook and check records nothing.
# One part alone: GUARDRAILS_TEST_PART=<n> in front. The parts are cut at the
# measured times of their hook calls (2026-11-12). Move a `part` line when a part grows.
#
# A case filter: CONVEYOR_SHELL_TEST_CASE=<text>[,<text>] runs only the top-level checks whose text
# holds one of the texts; lib/case-filter.sh says how. A part with no selected check prints `0 passed, 0 failed`
# and is accepted; each text must select a check in some part.
. "$(dirname "${BASH_SOURCE[0]}")/lib/case-filter.sh"
PARTS=2
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

# Outside its own part a call runs no hook, though each $(json ...) and $(run_hook ...) around it still forks a
# subshell; inside it, one more fork that becomes the hook (no echo or pipe forks).
run_hook() { [ "$ON" = 1 ] || return 0; ( cd "$MAIN_TMP" && exec "$HOOK" <<<"$1" >/dev/null 2>&1 ); echo $?; }
check() { [ "$ON" = 1 ] || return 0; if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected $2, got $3)"; fi }
# Outside its own part a run builds no payload: the parts each paid a jq per case for nothing.
# Inside it, the payload is escaped in bash: a jq per case cost about a seventh of the case. A control character
# other than tab, newline and CR takes jq's \u escape, so such a command still goes through jq.
json() {
  [ "$ON" = 1 ] || return 0
  local s=$1 t=${1//[$'\t\n\r']/}
  if [[ $t == *[[:cntrl:]]* ]]; then jq -cn --arg cmd "$1" '{tool_input:{command:$cmd}}'; return; fi
  s=${s//\\/\\\\}; s=${s//\"/\\\"}; s=${s//$'\t'/\\t}; s=${s//$'\n'/\\n}; s=${s//$'\r'/\\r}
  printf '{"tool_input":{"command":"%s"}}\n' "$s"
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
rm -rf "$READ_TMP"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
