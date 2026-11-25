#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Self-test for bash-guardrails.sh. Run directly. This file has the writes into source files from the shell; bash-guardrails.test.sh and bash-guardrails-refusals.test.sh have the other cases.
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
PARTS=3
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
. "$(dirname "${BASH_SOURCE[0]}")/lib/said.sh" # a FAIL line names the hook's last input (json notes each payload)

# Outside its own part a call runs no hook, though each $(json ...) and $(run_hook ...) around it still forks a
# subshell; inside it, one more fork that becomes the hook (no echo or pipe forks).
run_hook() { [ "$ON" = 1 ] || return 0; ( cd "$MAIN_TMP" && exec "$HOOK" <<<"$1" >/dev/null 2>&1 ); echo $?; }
# A FAIL line gives the input first and stays one line: a failure log reader takes FAIL lines and cuts them at 400 characters.
check() { [ "$ON" = 1 ] || return 0; if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); local m="$1 (expected $2, got $3)"; echo "FAIL$(said) ${m//$'\n'/\\n}"; fi }
# Outside its own part a run builds no payload: the parts each paid a jq per case for nothing.
# Inside it, the payload is escaped in bash: a jq per case cost about a seventh of the case. A control character
# other than tab, newline and CR takes jq's \u escape, so such a command still goes through jq.
json() {
  [ "$ON" = 1 ] || return 0
  local s=$1 t=${1//[$'\t\n\r']/}
  if [[ $t == *[[:cntrl:]]* ]]; then jq -cn --arg cmd "$1" '{tool_input:{command:$cmd}}' | said_tee; return; fi
  s=${s//\\/\\\\}; s=${s//\"/\\\"}; s=${s//$'\t'/\\t}; s=${s//$'\n'/\\n}; s=${s//$'\r'/\\r}
  printf -v s '{"tool_input":{"command":"%s"}}' "$s"; said_in "$s"; printf '%s\n' "$s"
}

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
w "stated limit: a copy behind sudo is not followed" 0 'sudo cp /tmp/x src/a.ts'
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

part 2
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
SEAT=run_hook
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

# A command-prefix wrapper hid the writer: the check read `env` or `nice` as the command, so `env sed -i` on a source
# file passed. Each wrapper, with its options and values, is now judged as the command behind it.
u() { check "wrapper: $1" "$2" "$(run_hook "$(json "$3")")"; }
u "env sed -i is refused" 2 "env sed -i 's/a/b/' src/x.ts"
u "env with NAME=value and -u NAME before perl -pi is refused" 2 "env -u HOME FOO=1 perl -pi -e 's/a/b/' src/x.ts"
u "env -S with the writer in its string is refused" 2 "env -S 'sed -i s/a/b/' src/x.ts"
u "nice sed -i is refused" 2 "nice sed -i 's/a/b/' src/x.ts"
u "nice -n 5: the value is not the command" 2 "nice -n 5 sed -i 's/a/b/' src/x.ts"
u "timeout 5 perl -pi is refused" 2 "timeout 5 perl -pi -e 's/a/b/' src/x.ts"
u "timeout -k 2 -s KILL 5: the values and the duration are not the command" 2 "timeout -k 2 -s KILL 5 sed -i 's/a/b/' src/x.ts"
u "command sed -i is refused" 2 "command sed -i 's/a/b/' src/x.ts"
u "nohup exec stdbuf -oL sed -i, wrappers stacked, is refused" 2 "nohup exec stdbuf -oL sed -i 's/a/b/' src/x.ts"
u "/usr/bin/time -o FILE sed -i is refused" 2 "/usr/bin/time -o /tmp/t sed -i 's/a/b/' src/x.ts"
u "env cp onto a hook is refused" 2 'env cp /tmp/x.sh .claude/hooks/x.sh'
u "find -exec env sed -i is refused" 2 "find src -name '*.ts' -exec env sed -i 's/a/b/' {} +"
u "xargs nice sed -i is refused" 2 "rg -l foo src | xargs nice sed -i 's/a/b/'"
u "env sed -i under /tmp passes" 0 "env sed -i 's/a/b/' /tmp/conveyor/x"
u "env ls passes" 0 'env ls src'
u "timeout 5 git status passes" 0 'timeout 5 git status'
u "env sed -n on a source path is a read and passes" 0 "env sed -n '1p' src/x.ts"
# GNU env reads a bare `-` as -i: the check kept `-` as the command name, so the sed behind it passed.
u "env - sed -i, the bare - option, is refused" 2 "env - sed -i 's/a/b/' src/x.ts"
# GNU env -S splits its string at an unquoted \_: the check read `sed_-i_s/a/b/` as one command name and passed it.
u "env -S with \\_ between the writer's words is refused" 2 "env -S 'sed\\_-i\\_s/a/b/' src/x.ts"
# GNU env drops a bare `-` after `--` too: the check kept it as the command name, so the sed behind it passed.
u "env -- - sed -i is refused" 2 "env -- - sed -i 's/a/b/' src/x.ts"
# Inside single quotes GNU env -S keeps \' as data: the check closed the quote there, glued -i into one quoted word
# with the \_ after the real close, and passed the sed.
u "env -S with \\' in single quotes before \\_-i is refused" 2 "env -S \"sed 'x\\''\\_-i s/a/b/\" src/x.ts"
# Bash's `time -p` keyword: the word reader dropped `time` and left `-p` as the command, so the sed behind it passed.
u "time -p sed -i is refused" 2 "time -p sed -i 's/a/b/' src/x.ts"
# Bash's `time -p --`: the word reader dropped `time` and `-p` but left `--` as the command, so the sed passed.
u "time -p -- sed -i is refused" 2 "time -p -- sed -i 's/a/b/' src/x.ts"
# The `--` after `time -p` is dropped, not judged: a check that refused the form, or read `--` as a writer, blocks a read.
u "time -p -- git status passes" 0 'time -p -- git status'
# macOS env -P takes a folder: the check read /usr/bin as the command, so the sed behind it passed.
u "env -P DIR sed -i is refused" 2 "env -P /usr/bin sed -i 's/a/b/' src/x.ts"
# GNU env takes `--unse` for --unset: the check read HOME, its value, as the command.
u "env --unse NAME, an abbreviated long option, is refused" 2 "env --unse HOME sed -i 's/a/b/' src/x.ts"
# `--split` for --split-string: the check did not split the string, so `sed -i` in it passed.
u "env --split, abbreviated -S, is refused" 2 "env --split 'sed -i s/a/b/' src/x.ts"
# env sets A.B=1 though it is no shell name: the check read it as the command.
u "env A.B=1 sed -i is refused" 2 "env A.B=1 sed -i 's/a/b/' src/x.ts"
# env -C /tmp runs sed in /tmp, so src/x.ts is /tmp/src/x.ts, scratch: the check judged it as the repo's source file.
u "env -C /tmp sed -i on a relative path passes" 0 "env -C /tmp sed -i 's/a/b/' src/x.ts"
# The env -C folder belongs to its own segment: kept, it would make the next segment's source write pass.
u "env -C /tmp does not carry to the next command" 2 "env -C /tmp true; sed -i 's/a/b/' src/x.ts"
# GNU env keeps only its last -C, so sed runs in ./src: the check joined src to /tmp and passed a source write.
u "env -C /tmp -C src: the last -C replaces the first" 2 "env -C /tmp -C src sed -i 's/a/b/' x.ts"
# Two -C to scratch leave sed in /tmp: a check that refused any second -C, or judged its folder as the repo, blocks a scratch write.
u "env -C /tmp -C /tmp sed -i on a relative path passes" 0 "env -C /tmp -C /tmp sed -i 's/a/b/' x.ts"
# command -v only names what tee is: the check read tee as the command and the hook as its target.
u "command -v -- tee on a hook path is a lookup and passes" 0 'command -v -- tee .claude/hooks/bash-guardrails.sh'
# No check in this hook judges ast-grep yet, so its verdict is the same with or without env whatever unwrap does. What
# this check owes the ast-grep rule is the unwrapped command: before, `env FOO=1 ast-grep run -U` was read as `env`.
if [ "$ON" = 1 ]; then # HOOK is `true` outside part 2: reading it there finds no unwrap
  eval "$(sed -n '/^env_split() {/,/^}/p;/^unwrap() {/,/^}/p' "$HOOK")"
  unwrap env FOO=1 ast-grep run -p a -r b -U src
fi
check "wrapper: env FOO=1 ast-grep run -p a -r b -U src unwraps to the ast-grep command" "ast-grep run -p a -r b -U src" "${WRAP[*]}"

part 3
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

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
