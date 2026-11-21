#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Pins git-safety's matching: a git call counts after &&, ;, | or an env prefix; --force-with-lease must pass; git -C <path> may sit before the subcommand.
set -u

HOOK="$(cd "$(dirname "$0")/.." && pwd)/git-safety.sh"
PASS=0 FAIL=0

# The file runs itself once per part, side by side, and prints the parts in
# order (the way bash-guardrails.test.sh does): a hook call costs about
# 80 ms and there are some 340. Every line runs in every part, so each part has
# every helper; outside its own part `run` starts nothing and `check` records
# nothing. One part alone: GIT_SAFETY_TEST_PART=<n> in front.
PARTS=4
if [ -z "${GIT_SAFETY_TEST_PART:-}" ]; then
  OUT=$(mktemp -d); trap 'rm -rf "$OUT"' EXIT
  for P in $(seq "$PARTS"); do GIT_SAFETY_TEST_PART=$P bash "$0" > "$OUT/$P" 2>&1 & done
  wait
  for P in $(seq "$PARTS"); do
    # A part that died before its count, or ran no case, is a failure, never a shorter list.
    if [[ $(tail -1 "$OUT/$P") =~ ^([0-9]+)\ passed,\ ([0-9]+)\ failed$ ]] && grep -qE '^(ok  |FAIL) ' "$OUT/$P"; then
      PASS=$((PASS+BASH_REMATCH[1])) FAIL=$((FAIL+BASH_REMATCH[2]))
      sed '$d' "$OUT/$P" | sed '${/^$/d;}'
    else
      cat "$OUT/$P"; echo "FAIL part $P of $PARTS did not finish"; FAIL=$((FAIL+1))
    fi
  done
  echo
  echo "$PASS passed, $FAIL failed"
  [ "$FAIL" -eq 0 ]; exit
fi
case "$GIT_SAFETY_TEST_PART" in [1-$PARTS]) ;; *) echo "FAIL no such part: $GIT_SAFETY_TEST_PART (parts: 1 to $PARTS)" >&2; exit 2 ;; esac
part() { if [ "$1" = "$GIT_SAFETY_TEST_PART" ]; then ON=1; else ON=0; fi; }

. "$(dirname "${BASH_SOURCE[0]}")/lib/said.sh" # a FAIL line names the hook's last input
check() { [ "$ON" = 1 ] || return 0; if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected $2, got $3)$(said)"; fi }
cmd() { jq -cn --arg c "$1" '{tool_name:"Bash", tool_input:{command:$c}}'; }
run() { [ "$ON" = 1 ] || return 0; bash "$HOOK" >/dev/null 2>&1 <<<"$(cmd "$1")"; echo $?; }

part 1
# --- 1. a git call anywhere in the command is screened ------------------------
check "a bare force push blocks"                2 "$(run 'git push --force origin main')"
check "a force push after && blocks"            2 "$(run 'cd /repo && git push --force origin main')"
check "a force push after ; blocks"             2 "$(run 'npm test ; git push --force')"
check "a force push after | blocks"             2 "$(run 'true | git push --force')"
check "a force push with an env prefix blocks"  2 "$(run 'FOO=1 git push --force origin main')"
check "a force push by absolute path blocks"    2 "$(run '/usr/bin/git push --force origin main')"
check "git push -f blocks"                      2 "$(run 'git push -f origin main')"
check "git push -f after && blocks"             2 "$(run 'cd /repo && git push -f')"
check "a reset --hard after && blocks"          2 "$(run 'cd /repo && git reset --hard origin/main')"

# --- 1b. options between the verb and its subcommand --------------------------
# `git -C <path>` is this repo's standard form, so an option may sit between git and its subcommand.
check "git -C <path> push --force blocks"       2 "$(run 'git -C /srv/repos/app push --force')"
check "git --no-pager push --force blocks"      2 "$(run 'git --no-pager push --force')"
check "git -C <path> reset --hard blocks"       2 "$(run 'git -C /repo reset --hard origin/main')"
check "git -c k=v push --force blocks"          2 "$(run 'git -c core.pager=cat push --force')"
check "two options before push blocks"          2 "$(run 'git --no-pager -C /repo push --force')"
check "git -C <path> push -f blocks"            2 "$(run 'git -C /repo push -f')"

# --- 1d. the other force and delete forms ----------------------------
check "git push -fu blocks"                     2 "$(run 'git push -fu origin main')"
check "git push -uf blocks"                     2 "$(run 'git push -uf origin main')"
check "a +refspec blocks"                       2 "$(run 'git push origin +main')"
check "a +src:dst refspec blocks"               2 "$(run 'git -C /repo push origin +HEAD:main')"
check "an empty-source :ref refspec blocks"     2 "$(run 'git push origin :main')"
check "git push --delete blocks"                2 "$(run 'git push --delete origin feature')"
check "git push origin --delete blocks"         2 "$(run 'cd /repo && git push origin --delete feature')"
check "git push -d blocks"                      2 "$(run 'git push -d origin feature')"
check "git push --mirror blocks"                2 "$(run 'git push --mirror origin')"
check "git push -u origin <branch> passes"      0 "$(run 'git push -u origin feature/some-unit')"
check "a src:dst refspec passes"                0 "$(run 'git push origin HEAD:refs/heads/feature')"
check "a + after the push command passes"       0 "$(run 'git push origin main && echo +1')"

# --- 1c. the repository-name blanket is gone ----------------------------------
# The guard refused any command whose text contained `sample-poc`, including
# a read-only clone or a remote listing. It kept out no destructive operation
# the force/reset checks do not already cover.
check "a sample-poc remote passes"           0 \
  "$(run "git remote add poc 'git@gh:x/sample-poc.git'")"
check "cloning sample-poc passes"            0 \
  "$(run 'cd /tmp && git clone sample-poc')"
check "a force push INTO sample-poc still blocks" 2 \
  "$(run 'git push --force poc main')"

# --- 2. --force-with-lease is the RECOMMENDED form and must pass --------------
check "--force-with-lease passes"               0 "$(run 'git push --force-with-lease origin main')"
check "--force-with-lease=ref passes"           0 "$(run 'git push --force-with-lease=main:abc123 origin main')"
check "--force-with-lease after && passes"      0 "$(run 'cd / && git push --force-with-lease')"
check "--force-if-includes passes"              0 "$(run 'git push --force-with-lease --force-if-includes')"
check "the message still recommends the lease form" 0 \
  "$(bash "$HOOK" 2>&1 >/dev/null <<<"$(cmd 'git push --force')" | grep -qF -- '--force-with-lease' && echo 0 || echo 1)"

# --- ordinary work is untouched ----------------------------------------------
check "an ordinary push passes"                 0 "$(run 'git push origin main')"
check "an ordinary git -C push passes"          0 "$(run 'git -C /repo push origin main')"
check "a plain status passes"                   0 "$(run 'git status --porcelain')"
# A subcommand is not an option, so the option group cannot swallow `log` and
# reach a later word. This is the over-match the widened pattern must not have.
check "git log with a ref named push passes"    0 "$(run 'git log --oneline push')"
check "git -C <path> status passes"             0 "$(run 'git -C /repo status')"
check "git -C <path> --force-with-lease passes" 0 "$(run 'git -C /repo push --force-with-lease')"
check "a non-git command passes"                0 "$(run 'npm run test:guards')"
check "a soft reset passes"                     0 "$(run 'git reset --soft HEAD~1')"
check "an ordinary push is SILENT"              "" "$(bash "$HOOK" 2>&1 <<<"$(cmd 'git push origin main')")"
check "malformed JSON passes rather than wedging" 0 "$(run 'not json')"

# --- quoted text is not a command --------------------------------------------
# A commit message or an echo that NAMES a dangerous operation must not block.
check "a commit message naming a force push passes" 0 \
  "$(run "git commit -m 'never run git push --force here'")"
check "an echo naming a force push passes"          0 \
  "$(run 'echo "do not use git push --force"')"

# --- multi-line messages are data too ---------------------------------
# The quote strip ran line by line, so a quote or heredoc spanning lines was
# never stripped and the repo's standard heredoc commit form blocked.
check "a heredoc commit message naming reset --hard passes" 0 \
  "$(run $'git commit -m "$(cat <<\'EOF\'\nfix: stop using git reset --hard here\nEOF\n)"')"
check "a two-line quoted message naming a force push passes" 0 \
  "$(run $'git commit -m "first line\nnever git push --force"')"
check "commit -F - with a heredoc naming push -f passes" 0 \
  "$(run $'git commit -F - <<EOF\nwhy we never git push -f origin main\nEOF')"
check "a real force push after a heredoc commit still blocks" 2 \
  "$(run $'git commit -F - <<EOF\nmsg\nEOF\ngit push --force')"
# A heredoc ends on the line bash ends it on: an indented look-alike of the end
# word is still body, and an apostrophe after it must not swallow the push.
check "a force push after a heredoc holding an indented look-alike of its end word still blocks" 2 \
  "$(run $'cat <<\'EOF\'\n  EOF\nIt\'s\nEOF\ngit push --force')"
check "the same with a tab, which ends a heredoc only under <<-" 2 \
  "$(run $'cat <<\'EOF\'\n\tEOF\nIt\'s\nEOF\ngit push --force')"
check "under <<- a tabbed end word ends the heredoc and the push after it blocks" 2 \
  "$(run $'cat <<-\'EOF\'\n\tIt\'s\n\tEOF\ngit push --force')"
check "under <<- a heredoc naming push -f still passes" 0 \
  "$(run $'cat <<-\'EOF\'\n\twhy we never git push -f origin main\n\tEOF')"
# An end word that is not plain never reaches this hook: bash-guardrails.sh
# refuses the command, so this hook reads no odd end word. Every form review
# found that hid a force push after the note:
for E in "<<'END NOTE'" "<<E'OF'" "<<'E'OF" '<<"E""OF"' "<<E\\OF" "<<'END'\\ NOTE" '<<"E\"OF"'; do
  check "a force push after a heredoc with the end word $E is refused" 2 \
    "$(bash "${HOOK%/*}/bash-guardrails.sh" >/dev/null 2>&1 <<<"$(cmd "$(printf 'cat %s\nmsg\nEOF\ngit push --force' "$E")")"; echo $?)"
done
check "a real reset --hard inside \$(...) in quotes still blocks" 2 \
  "$(run 'echo "$(git reset --hard HEAD)"')"
check "an empty quote inside push does not dodge the prefilter" 2 \
  "$(run "git pu''sh --force")"
# Without its strip helper the hook must refuse, not read an empty command.
LONE=$(mktemp -d); cp "$HOOK" "$LONE/"
check "a missing strip-quoted.sh blocks"        2 \
  "$(bash "$LONE/git-safety.sh" >/dev/null 2>&1 <<<"$(cmd 'git push --force')"; echo $?)"
rm -rf "$LONE"

part 2
# --- 3. the other ways to discard work ---------------------------------
# reset --hard was the only discard this hook knew. Each family below throws
# away uncommitted edits, untracked files, a stash, an unmerged branch or the
# reflog that would recover them, and each sits beside ordinary work that must
# keep passing: a branch checkout is not a path checkout. Every family runs
# bare and behind a `git -C` / `git -c` option. Payloads are only screened,
# never run.
blocks() { for C in "$@"; do check "blocks: $C" 2 "$(run "$C")"; done; }
passes() { for C in "$@"; do check "passes: $C" 0 "$(run "$C")"; done; }
blocks 'git checkout -- .' 'git checkout .' 'git checkout HEAD -- src/x.ts' \
  'git -C /repo checkout -- .' 'git -c core.pager=cat checkout .' 'git checkout -- "my file.txt"'
passes 'git checkout feature' 'git checkout -q --detach abc1234' 'git checkout -b feature/new-unit' \
  'git -C /repo checkout feature' 'git --no-pager checkout feature'
blocks 'git restore .' 'git restore --worktree src/x.ts' 'git restore --staged --worktree src/x.ts' \
  'git restore -SW src/x.ts' 'git -C /repo restore .' 'git restore "my file.txt"'
passes 'git restore --staged src/x.ts' 'git restore -S src/x.ts' 'git -C /repo restore --staged "my file.txt"'
blocks 'git clean -fdx' 'git clean -xdf' 'git clean --force -d' 'git clean -d --force' 'git -C /repo clean -fd'
passes 'git clean -ndx' 'git clean -nfdx' 'git clean --dry-run -fdx' 'git -C /repo clean -n'
blocks 'git stash drop' 'git stash drop stash@{0}' 'git stash clear' 'git -C /repo stash drop'
passes 'git stash list' 'git stash show' 'git stash show -p stash@{0}' 'git -C /repo stash list'
blocks 'git branch -D feature' 'git branch --delete --force feature' 'git branch --force --delete feature' \
  'git branch -d -f feature' 'git -c advice.detachedHead=false branch -D feature'
passes 'git branch -d merged' 'git branch --list' 'git branch --show-current' 'git -C /repo branch -d merged'
blocks 'git worktree remove --force /tmp/wt' 'git worktree remove -f /tmp/wt' \
  'git worktree remove /tmp/wt --force' 'git -C /repo worktree remove --force /tmp/wt'
passes 'git worktree list' 'git worktree remove /tmp/wt' 'git -C /repo worktree list'
blocks 'git reflog expire --expire=now --all' 'git reflog expire --all' \
  'git -C /repo reflog expire --expire-unreachable=now --all'
passes 'git reflog' 'git reflog show' 'git -C /repo reflog show'
blocks 'git gc --prune=now' 'git gc --aggressive --prune=now' 'git -C /repo gc --prune=now'
passes 'git gc' 'git gc --no-prune' 'git -C /repo gc'
# Each git call is judged on its own arguments, wherever it sits in the command.
blocks 'cd /repo && git checkout -- . ; echo "done"' 'FOO=1 git clean -fdx' 'npm test || git stash drop' \
  'echo "$(git restore .)"' '/usr/bin/git branch -D feature' $'git status\ngit clean -fdx'
passes "git commit -m 'never run git clean -fdx or git checkout -- . here'" \
  'git status; echo "git stash clear"' 'git checkout feature; echo -- .' 'git branch --list && rm -f x' \
  'git worktree list | grep -- --force' $'git commit -F - <<EOF\nwhy we never git branch -D or git gc --prune=now\nEOF'
# A script may run restore, checkout and worktree cleanup inside itself; the
# hook sees the submitted command, which names no git call.
passes 'bash conveyor/conveyor.sh run'
# A quoted argument is still an argument. Quoted spans were removed outright,
# so `git -C "/repo" clean -fdx` lost the option's value, the option took
# `clean` as its value instead, and the discard passed. A quoted span that is
# one plain token is the word bash passes; quoted prose is still data. The two
# reported inputs are pinned in git-safety-quoted-options.refute.test.sh.
blocks 'git -C "/repo" clean -fdx' 'git -c "core.pager=cat" clean -fdx' "git -C '/repo' stash drop" \
  'git -C "/my repo" clean -fdx' 'git --git-dir "/repo/.git" branch -D feature' \
  'git clean "-fdx"' 'git checkout "."' 'git "clean" -fdx' 'git cl"ea"n -fdx' 'git stash "drop"' \
  'git -C "$(pwd)" clean -fdx'
passes 'git -C "/repo" checkout feature' 'git -c "core.pager=cat" stash list' 'git -C "/my repo" clean -n' \
  'git -C "/repo" branch -d "merged"' 'git checkout "feature"' \
  "git -C \"/repo\" commit -m 'never run git clean -fdx here'" 'git commit -m "clean" -m "-fdx"'
# Everything after `--` is a path, quoted or not: a file named -n is not a dry
# run and a file named --staged does not make a restore index-only.
blocks 'git clean -f -- "-n"' 'git clean -f -- -n' 'git restore -- "--staged"' 'git restore -- --staged'
passes 'git clean -n -- "-f"' 'git restore --staged -- "src/x.ts"'
# Quoted data is never the start of a git call, and a bare `--` is not a git
# option, so a search term or a file name cannot read as a second invocation.
passes 'git grep -n "git" -- "restore"' 'git grep -n git -- restore' 'git log --grep "git" -- "stash" "drop"' \
  'git restore-mtime' 'git clean-merged -f'
check "a discard refusal says what was refused" 1 \
  "$(bash "$HOOK" 2>&1 >/dev/null <<<"$(cmd 'git clean -fdx')" | grep -c 'git clean')"

part 3
# --- 4. a quoted subcommand is still the subcommand --------------------
# The force-push and hard-reset checks read the command with every quoted span
# removed, so `git -C /repo 'push' --force` had no subcommand left to match and
# passed. Bash runs it exactly as the unquoted form.
blocks "git -C /repo 'push' --force" 'git -C /repo "reset" --hard' "git 'push' --force origin main" \
  'git "reset" --hard HEAD' 'git -C /repo "push" -f' 'git -C "/repo" pu"sh" origin +main' \
  'git --no-pager "push" --mirror' 'git -C /repo "push" origin --delete feature' 'git push "--force" origin main' \
  'git reset "--hard"'
# Every other destructive form, quoted, with and without a global option.
blocks 'git "clean" -fdx' 'git -C /repo "clean" -fdx' 'git "branch" -D feature' 'git -C /repo "branch" -D feature' \
  'git "checkout" -- .' 'git -C /repo "checkout" -- .' "git 'restore' ." "git -C /repo 'restore' ." \
  'git "stash" drop' 'git -C /repo "stash" clear' 'git "worktree" remove --force /tmp/wt' \
  'git -C /repo "worktree" remove --force /tmp/wt' 'git -C /repo "reflog" expire --all' 'git -C /repo "gc" --prune=now'
# Quoted prose that names a force push is still data, and the quoted safe forms pass.
passes "git commit -m 'never push --force here' && git push origin main" 'git -C /repo "push" origin main' \
  'git -C /repo "push" --force-with-lease origin main' 'git -C /repo "reset" --soft HEAD~1' \
  'git log --grep "--force" && git push origin main' 'git commit -m "reset --hard is blocked" -m "push -f too"'

# --- 5. a path checkout written as commit plus path, no `--` -----------
# `git checkout HEAD src/file.ts` overwrites the file's uncommitted edits. A
# branch checkout never takes a second positional argument, unless it makes the
# branch (-b, -B, --orphan take a start point).
blocks 'git checkout HEAD src/file.ts' 'git checkout main src/a.ts src/b.ts' 'git -C /repo checkout HEAD~1 "my file.txt"' \
  'git checkout -q HEAD src/x.ts' 'git checkout "HEAD" "src/x.ts"'
passes 'git checkout feature' 'git checkout -b new-unit origin/main' 'git checkout -B new-unit origin/main' \
  'git checkout --orphan fresh main' 'git checkout -qb new-unit origin/main' 'git checkout --track -b new-unit origin/x' \
  'git checkout feature 2>/dev/null' 'git checkout feature > /tmp/checkout.log' 'git checkout -q --detach abc1234 >/dev/null'
check "a commit-plus-path refusal is the checkout-of-paths one" 1 \
  "$(bash "$HOOK" 2>&1 >/dev/null <<<"$(cmd 'git checkout HEAD src/file.ts')" | grep -c 'git checkout of paths')"

# --- 6. the flag is read wherever it sits in the call ------------------
# `reset` had to be followed at once by `--hard`, `switch` was never screened
# and `checkout -f` read as a branch checkout: each throws away uncommitted
# edits. git also takes any unambiguous start of a long option (`--har`).
blocks 'git reset HEAD --hard' 'git reset -q --hard' 'git -C /repo reset origin/main --hard' 'git reset --har' \
  'git checkout -f main' 'git checkout --force main' 'git checkout -qf main' 'git checkout main --forc' \
  'git switch -f main' 'git switch --force main' 'git switch --discard-changes' 'git switch main --discard' \
  'git -C /repo "switch" -f main' "git push '--force'" "git reset '--hard'" \
  'git restore --staged --work .' 'git clean --forc -d' 'git branch --del --forc old' \
  'git worktree remove --for /tmp/wt' 'git gc --pru=now' 'git push origin --del old' 'git push --mir origin'
passes 'git reset --soft HEAD~1' 'git reset HEAD -- src/x.ts' 'git reset -q HEAD' 'git switch main' 'git switch -c new-unit origin/main' \
  'git switch --detach abc1234' 'git reset --soft HEAD~1 && echo --hard' 'git switch main; ls -f' \
  'git commit -m "reset HEAD --hard is blocked" && git switch main' 'git push --dry-run origin main' \
  'git log --format=%s -- src/hard' 'git reset --mixed HEAD -- --hard'

# --- 7. a force flag belongs to the push, not to the next command ------
passes 'git push origin HEAD && rg -f patterns.txt src/' 'git push origin HEAD; echo --force' \
  'git push origin HEAD | tee -f /tmp/log' 'git push origin HEAD || grep -f pats.txt --force x'
blocks 'git push origin HEAD --force && rg -f patterns.txt src/' 'git push origin main -f; ls' \
  'git fetch && git push origin main --force'

part 4
# --- 8. a quoted git word runs git, wherever it stands -------------------------
# Bash runs `"git"` exactly as `git`. Reading a quoted git word as data let the
# discard through behind an assignment or a wrapper, and each wrapper taught to
# the hook left the next one open. Every git word is read as a call instead.
blocks 'FOO=1 "git" "reset" --hard' '"git" "reset" --hard' 'env "git" clean -fdx' 'env -u git "git" reset --hard' \
  'sudo -u git "git" clean -fdx' "'git' push --force" '"/usr/bin/git" stash drop' 'cd /repo && "git" checkout -- .' \
  'nice -n 5 "git" branch -D feature'
passes '"git" status' 'FOO=1 "git" log --oneline' 'git commit -m "git"' 'env "git" clean -n' '"git" push origin main' \
  'git commit -m "git reset --hard is bad"'
# The stated limit of that rule: a git word that is data, followed by words that
# spell a discard, is refused too. The way past is to reword the command.
blocks 'git status; grep -c "git" stash drop' 'git status; echo "/usr/bin/git" restore'
# Backticks run inside double quotes, and nested ones cannot be told from data
# by their quotes. A command holding a backtick is read with no quotes at all.
blocks 'echo "`git reset --hard`"' 'echo "`echo "`printf x`"`"; git reset --hard' 'X="`git clean -fdx`"' \
  'echo "`echo "`printf x`"`"; git clean -fdx' 'echo "`echo "`printf x`"`"; git restore .'
passes 'echo "`date`"; git status' 'git commit -m "note `x` here" && git push origin main' 'echo `git rev-parse HEAD`'
# Dropping the quotes must not split a quoted argument: a path with a space
# stays one word, or the discard after it is read as a harmless subcommand.
blocks 'echo `date`; git -C "/tmp/my repo" reset --hard' 'echo `date`; git -C "/tmp/my repo" push --force origin main' \
  "echo \`date\`; git -C '/tmp/my  repo' clean -fdx"
passes 'echo `date`; git -C "/tmp/my repo" status'
# Nor may a separator inside a quoted path: the discard after it is still read.
blocks 'echo `date`; git -C "/tmp/my; repo" reset --hard' 'echo `date`; git -C "/tmp/my; repo" push --force origin main' \
  "echo \`date\`; git -C '/tmp/a|b' clean -fdx" 'echo `date`; git -C "/tmp/my; repo" restore .'
passes 'echo `date`; git -C "/tmp/my; repo" status'
# A backtick may be the option value itself, quoted or bare: no reading of the
# quotes keeps that apart, so a backtick beside a git call and a discarding
# word is refused whole.
blocks 'git -C "`realpath .`" reset --hard' 'git -C "`realpath .`" push --force origin main' 'git -C "`realpath .`" clean -fdx' \
  'git -C `realpath .` reset --hard' 'git -C "/x/`whoami`/my repo" branch -D gone' 'git -C "`pwd`" stash drop' 'git -C "`pwd`" restore .'
passes 'git -C "`realpath .`" status' 'git diff --stat `git merge-base main HEAD`' 'git push -u origin `git branch --show-current`' \
  'git -C /repo push --force-with-lease origin `git branch --show-current`' 'git branch -d `cat /tmp/merged`'
# No word list decides: the closed reading goes through every check, so the
# shortened and less common forms are refused as they are without a backtick.
blocks 'git -C "`realpath .`" reset --har' 'git -C "`realpath .`" push origin -d topic' 'git -C "`realpath .`" clean --forc -d' \
  'git -C "`realpath .`" checkout HEAD src/file.ts'
passes 'git status; echo "reset --hard is forbidden" `date`'
# Beside a backtick, a $(...) inside a quoted string still runs and is read, one inside another too.
blocks 'echo `date`; echo "$(git reset --hard HEAD)"' 'echo `date`; X="$(git push --force origin main)"' \
  'echo `date`; echo "a $(echo "b $(git clean -fdx)")"' 'echo "`date` $(git stash drop)"' 'echo `date`; echo "$(cd /repo && git branch -D gone)"'
passes 'echo `date`; echo "$(git status)"' 'echo `date`; git commit -m "plain message"' 'echo `date`; echo "$(date): reset --hard is forbidden"'
# `<<` inside arithmetic is a shift and opens no note, so the lines after it are still read.
blocks $'echo $((1<<2))\ngit push --force origin main' $'((X = 1<<2))\ngit reset --hard HEAD' $'echo $[1<<2]\ngit clean -fdx' \
  $'X=$((Y<<=2)); echo $X\ngit stash drop' $'if ((1<<2 > 3)); then echo big; fi\ngit push -f origin main' $'echo $(( (1<<2) + 1 ))\ngit reset --hard'
# Arithmetic runs inside double quotes too, so a shift there opens no note either.
blocks $'echo "$((1<<2))"\ngit push --force origin main' $'X="a $((1<<2)) b"\ngit reset --hard HEAD' $'echo "$(echo $((1<<2)))"\ngit stash drop' \
  $'echo "$[1<<2]"\ngit clean -fdx' $'echo "$(( (1<<2) + 1 ))"\ngit push -f origin main'
passes $'echo "$((1<<2))"\ngit status' $'echo "$((1<<2))"\ncat <<EOF\ngit reset --hard\nEOF' \
  $'echo "$( (echo a) | cat <<EOF\ngit reset --hard\nEOF\n)"'
passes $'echo $((1<<2))\ngit push origin main'$'cat <<EOF\ngit push --force origin main\nEOF\ngit status' \
  $'cat <<2\ngit reset --hard\n2\ngit status' $'echo $((1<<2))\ncat <<EOF\ngit reset --hard\nEOF'
# A quoted command word is never hidden: the executable and its subcommand are read through their quotes.
blocks 'echo `date`; "git" "reset" --hard' 'echo `date`; FOO=1 "git" "reset" --hard' "echo \`date\`; 'git' 'clean' -fdx" \
  'echo `date`; "/usr/bin/git" "push" "--force" origin main'
# An escaped quote opens no string, and a backslash ends none inside single quotes.
blocks 'echo \" `date`; git reset --hard; echo \"' "echo 'a\\' \`date\`; git reset --hard; echo 'b'"
# Its stated limit: quoted prose that names a discard beside a backtick is refused.
blocks "git commit -m 'never run \`git reset --hard\` here'"

# --- 9. a forced remove passes for a clean worktree anywhere; only uncommitted work blocks it ----------
# The owner's rule: nothing is recorded about who added what, and the folder a
# worktree sits in no longer matters. Real worktrees, edits and removes, with the hook judging each forced remove from
# its PreToolUse payload. S and T are two sessions; $F and $FT their folders. Every ordering the review passes found
# is replayed, then each piece of state is taken away.
GS_S="" GS_T="" F="" FT="" B="" OUTSIDE=""
if [ "$ON" = 1 ]; then
  GS_S=gs-s-$$ GS_T=gs-t-$$
  F=/tmp/claude-session-$GS_S FT=/tmp/claude-session-$GS_T
  B=$(mktemp -d /tmp/gs-b.XXXXXX); OUTSIDE=$(mktemp -d /var/tmp/gs-out.XXXXXX)
  mkdir -p "$F" "$FT"
  trap 'rm -rf "$F" "$FT" "/tmp/claude-session-gs-s2-$$" "/tmp/claude-session-gs-s3-$$" "$B" "$OUTSIDE"' EXIT
  G() { env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE git -C "$B/repo" "$@"; }
  git init -q "$B/repo" && git init -q "$B/sub" && G config user.email t@t && G config user.name t \
    && git -C "$B/sub" -c user.email=t@t -c user.name=t commit -q --allow-empty -m sub \
    && echo base >"$B/repo/f" && G add f && G -c protocol.file.allow=always submodule add -q "$B/sub" sm >/dev/null 2>&1 \
    && G commit -q -m base
fi
gs_payload() { # <session, or empty for none> <command>
  jq -cn --arg s "$1" --arg c "$2" '{hook_event_name: "PreToolUse", tool_name: "Bash", tool_input: {command: $c}} + (if $s == "" then {} else {session_id: $s} end)'
}
gs_remove() { # <session> <path> [<flag>]: the forced remove's exit code
  [ "$ON" = 1 ] || return 0
  gs_payload "$1" "git worktree remove ${3---force} $2" | bash "$HOOK" >/dev/null 2>&1; echo $?
}
gs_add() { [ "$ON" = 1 ] || return 0; G worktree add -q --detach "$@" >/dev/null 2>&1; }
gs_edit() { [ "$ON" = 1 ] || return 0; echo t-edit >>"$1/f"; }
GS_GOT="" GS_WANT=""
# <label> <got> <want>; a case that differs carries the input of its own hook call, as the check names only the last.
gs_case() { GS_WANT+="$1=$3 "; if [ "$2" = "$3" ]; then GS_GOT+="$1=$2 "; else GS_GOT+="$1=$2$(said) "; fi; }

# Orderings. S's own clean worktree: passes, in every spelling of its path.
gs_add "$F/own" HEAD
[ -d /private/tmp ] && GS_ALIAS=0 || GS_ALIAS=2 # the /private/tmp form exists on a Mac only
gs_case own "$(gs_remove "$GS_S" "$F/own")" 0
gs_case own-short-f "$(gs_remove "$GS_S" "$F/own" -f)" 0
gs_case own-trailing-slash "$(gs_remove "$GS_S" "$F/own/")" 0
gs_case own-private-alias "$(gs_remove "$GS_S" "/private$F/own")" "$GS_ALIAS"
# Its add ran and no hook ran after it (calls overlapping, or cut off): nothing recorded is needed.
gs_add "$F/a" HEAD
gs_case no-after-step "$(gs_remove "$GS_S" "$F/a")" 0
# T's edited worktree in T's folder, after S's add on that path failed inside `; true`.
gs_add "$FT/w" HEAD; gs_edit "$FT/w"; gs_add "$FT/w" HEAD
gs_case other-session-folder "$(gs_remove "$GS_S" "$FT/w")" 2
# S's add of a bad ref fails; T adds that path in S's folder and edits it; S's own next add is still S's to remove.
gs_add "$F/foreign" no-such-ref; gs_add "$F/foreign" HEAD; gs_edit "$F/foreign"; gs_add "$F/own4" HEAD
gs_case foreign-edited "$(gs_remove "$GS_S" "$F/foreign")" 2
gs_case own-after-foreign "$(gs_remove "$GS_S" "$F/own4")" 0
# Pass 6: S removes its worktree, T adds one at the same path and edits it.
gs_add "$F/rw" HEAD; [ "$ON" = 1 ] && G worktree remove "$F/rw"; gs_add "$F/rw" HEAD; gs_edit "$F/rw"
gs_case replaced-edited "$(gs_remove "$GS_S" "$F/rw")" 2
# Pass 7: the same, then S's old after-call step (the deleted --record-add) arrives anyway: it changes nothing.
gs_add "$F/rw7" HEAD; [ "$ON" = 1 ] && G worktree remove "$F/rw7"; gs_add "$F/rw7" HEAD; gs_edit "$F/rw7"
gs_case old-after-step "$( [ "$ON" = 1 ] || exit 0
  jq -cn --arg s "$GS_S" --arg c "git worktree add --detach $F/rw7 HEAD" \
    '{hook_event_name: "PostToolUse", session_id: $s, tool_use_id: "tu1", tool_name: "Bash", tool_input: {command: $c}, tool_response: {is_error: false}}' \
    | bash "$HOOK" --record-add 2>&1; echo "rc$?")" rc0
gs_case delayed-replaced "$(gs_remove "$GS_S" "$F/rw7")" 2
gs_case t-edits-kept "$( [ "$ON" = 1 ] || exit 0; cat "$FT/w/f" "$F/foreign/f" "$F/rw/f" "$F/rw7/f" | grep -c t-edit)" 4
# Each piece of state taken away, or one change made, blocks.
GS_S2=gs-s2-$$; gs_add "/tmp/claude-session-$GS_S2/w" HEAD; [ "$ON" = 1 ] && rm -rf "/tmp/claude-session-$GS_S2"
gs_case folder-gone "$(gs_remove "$GS_S2" "/tmp/claude-session-$GS_S2/w")" 2
gs_add "$F/nogit" HEAD; [ "$ON" = 1 ] && rm -f "$F/nogit/.git"
gs_case not-a-worktree "$(gs_remove "$GS_S" "$F/nogit")" 2
gs_add "$F/n" HEAD
gs_case no-session-id "$(gs_remove "" "$F/n")" 0
gs_add "$F/u" HEAD; [ "$ON" = 1 ] && echo draft >"$F/u/draft.txt"
gs_case untracked "$(gs_remove "$GS_S" "$F/u")" 2
gs_case untracked-hidden-by-config "$( [ "$ON" = 1 ] || exit 0; G config status.showUntrackedFiles no; gs_remove "$GS_S" "$F/u"; G config --unset status.showUntrackedFiles)" 2
gs_add "$F/st" HEAD; [ "$ON" = 1 ] && echo staged >>"$F/st/f" && git -C "$F/st" add f
gs_case staged "$(gs_remove "$GS_S" "$F/st")" 2
# An edit hidden from status by an index flag is still work the forced remove would destroy.
gs_add "$F/au" HEAD; [ "$ON" = 1 ] && echo hidden >>"$F/au/f" && git -C "$F/au" update-index --assume-unchanged f
gs_case assume-unchanged-edit "$(gs_remove "$GS_S" "$F/au")" 2
gs_add "$F/sw" HEAD; [ "$ON" = 1 ] && echo hidden >>"$F/sw/f" && git -C "$F/sw" update-index --skip-worktree f
gs_case skip-worktree-edit "$(gs_remove "$GS_S" "$F/sw")" 2
gs_add "$F/sm" HEAD
gs_case submodule-hidden-by-config "$( [ "$ON" = 1 ] || exit 0
  git -C "$F/sm" -c protocol.file.allow=always submodule update -q --init >/dev/null 2>&1; echo x >"$F/sm/sm/inside.txt"
  G config diff.ignoreSubmodules all; gs_remove "$GS_S" "$F/sm"; G config --unset diff.ignoreSubmodules)" 2
gs_add "$B/out" HEAD; [ "$ON" = 1 ] && ln -s "$B/out" "$F/l"
gs_case symlink-out-of-folder "$(gs_remove "$GS_S" "$F/l")" 0
GS_S3=gs-s3-$$; [ "$ON" = 1 ] && mkdir -p "$B/s3" && ln -s "$B/s3" "/tmp/claude-session-$GS_S3"; gs_add "$B/s3/w" HEAD
gs_case folder-is-a-symlink "$(gs_remove "$GS_S3" "/tmp/claude-session-$GS_S3/w")" 0
gs_add "$F/b" HEAD; [ "$ON" = 1 ] && mkdir -p "$F/z"
gs_case dotdot "$(gs_remove "$GS_S" "$F/z/../b")" 2
gs_case two-paths "$(gs_remove "$GS_S" "$F/own $F/a")" 2
check "clean_worktree_force_remove_passes: a forced remove passes for a clean worktree and blocks one with any uncommitted work, in every ordering found so far" \
  "$GS_WANT" "$GS_GOT"

# clean_worktree_force_remove_passes: the session-folder test refused clean worktrees anywhere else (guard audit item 7);
# only uncommitted work blocks now. A session-folder test that returns blocks these two.
gs_add "$B/x" HEAD
check "clean_worktree_force_remove_passes: a clean worktree outside any session folder passes" 0 "$(gs_remove "$GS_S" "$B/x")"
check "a remove without --force is not screened" 0 "$(gs_remove "$GS_S" "$B/x" "")"
gs_add "$OUTSIDE/w8" HEAD
check "clean_worktree_force_remove_passes: a clean worktree outside /tmp passes" 0 "$(gs_remove "$GS_S" "$OUTSIDE/w8")"
gs_add "$OUTSIDE/w9" HEAD; gs_edit "$OUTSIDE/w9"
check "clean_worktree_force_remove_passes: a dirty worktree outside any session folder still blocks" 2 "$(gs_remove "$GS_S" "$OUTSIDE/w9")"

# scratch_worktree_force_remove: a stash-free scratch worktree under ${TMPDIR:-/tmp}/conveyor that holds edits could
# not be removed at all. Only a path that really sits strictly inside ${TMPDIR:-/tmp}/conveyor/ is let through.
TD=${TMPDIR:-/tmp}; TD=${TD%/}
PP=$TD/conveyor/gs-wt-$$ PO=$TD/conveyor-other-gs-$$ PX=$TD/gs-pp-x-$$
[ "$ON" = 1 ] && mkdir -p "$PP" "$PO"
gs_add "$PP/w" HEAD; gs_edit "$PP/w"
check "scratch_worktree_force_remove: a dirty worktree under the temp folder's conveyor/ passes" 0 "$(gs_remove "$GS_S" "$PP/w")"
# Bug caught: a lookalike path (no boundary, an escape, a symlink out, the root) grants the forced remove of real work.
GS_GOT="" GS_WANT=""
gs_add "$PO/x" HEAD; gs_edit "$PO/x"; gs_add "$PX" HEAD; gs_edit "$PX"
[ "$ON" = 1 ] && ln -s "$OUTSIDE/w9" "$PP/link"
gs_case sibling-prefix "$(gs_remove "$GS_S" "$PO/x")" 2
gs_case dotdot-escape "$(gs_remove "$GS_S" "$TD/conveyor/../${PX#"$TD"/}")" 2
gs_case symlink-out "$(gs_remove "$GS_S" "$PP/link")" 2
gs_case root-itself "$(gs_remove "$GS_S" "$TD/conveyor")" 2
gs_case two-paths "$(gs_remove "$GS_S" "$PP/w $OUTSIDE/w9")" 2
check "scratch_worktree_force_remove: a path only looking like it is under the temp folder's conveyor/ still blocks" "$GS_WANT" "$GS_GOT"
[ "$ON" = 1 ] && rm -rf "$PP" "$PO" "$PX" && G worktree prune

# --- 10. --ours/--theirs on a conflicted file mid-merge or mid-rebase ----------------------------------
# A Builder keeps one side of a conflicted file with `git checkout --ours -- f`, which the path-checkout rule refused.
# ours_on_conflicted_file_passes: it passes for paths git lists as unmerged. ours_outside_conflict_blocks: any other
# path, or no merge at all, is a plain overwrite of uncommitted edits and still blocks.
gs_in() { # <dir> <command>: the hook's exit code with that dir as the working folder
  [ "$ON" = 1 ] || { echo 0; return 0; }
  (cd "$1" && gs_payload "" "$2" | bash "$HOOK" >/dev/null 2>&1; echo $?)
}
CF=""
if [ "$ON" = 1 ]; then
  CF=$B/conf; git init -q "$CF" && git -C "$CF" config user.email t@t && git -C "$CF" config user.name t
  echo base >"$CF/f"; echo base >"$CF/g"; git -C "$CF" add f g; git -C "$CF" commit -q -m base
  git -C "$CF" checkout -q -b other; echo theirs >"$CF/f"; git -C "$CF" commit -q -am other
  git -C "$CF" checkout -q -; echo ours >"$CF/f"; git -C "$CF" commit -q -am mine
  git -C "$CF" merge other >/dev/null 2>&1
fi
check "ours_on_conflicted_file_passes: checkout --ours of the conflicted file" 0 "$(gs_in "$CF" 'git checkout --ours -- f')"
check "ours_on_conflicted_file_passes: checkout --theirs of the conflicted file" 0 "$(gs_in "$CF" 'git checkout --theirs -- f')"
check "ours_on_conflicted_file_passes: restore --ours of the conflicted file" 0 "$(gs_in "$CF" 'git restore --ours -- f')"
check "ours_outside_conflict_blocks: checkout --ours of a file not in conflict" 2 "$(gs_in "$CF" 'git checkout --ours -- g')"
check "ours_outside_conflict_blocks: one conflicted path and one not" 2 "$(gs_in "$CF" 'git checkout --ours -- f g')"
check "ours_outside_conflict_blocks: restore --theirs of a file not in conflict" 2 "$(gs_in "$CF" 'git restore --theirs -- g')"
check "ours_outside_conflict_blocks: no merge in progress" 2 "$(gs_in "$B/repo" 'git checkout --ours -- f')"
# The conflict is read where the command runs: its -C dirs, in order, as git enters them (pass 5). A form that cannot be
# resolved blocks; a CDPATH in the hook's environment must not move a relative -C somewhere git would not go.
check "ours_on_conflicted_file_passes: -C names the conflicted worktree" 0 "$(gs_in "$B/repo" "git -C $CF checkout --ours -- f")"
check "ours_on_conflicted_file_passes: -C restore --theirs in the conflicted worktree" 0 "$(gs_in "$B/repo" "git -C $CF restore --theirs f")"
check "ours_on_conflicted_file_passes: relative -C dirs chain" 0 "$(gs_in "$B/repo" "git -C $B -C conf checkout --ours -- f")"
check "ours_outside_conflict_blocks: -C names a clean worktree while the hook dir is conflicted" 2 "$(gs_in "$CF" "git -C $B/repo checkout --ours -- f")"
check "ours_outside_conflict_blocks: -C names the conflicted worktree but not the conflicted file" 2 "$(gs_in "$B/repo" "git -C $CF checkout --ours -- g")"
check "ours_outside_conflict_blocks: --git-dir cannot be resolved" 2 "$(gs_in "$CF" "git --git-dir=$B/repo/.git checkout --ours -- f")"
check "ours_outside_conflict_blocks: CDPATH does not resolve a relative -C" 2 \
  "$([ "$ON" = 1 ] || { echo 2; exit; }; cd "$B/repo" && gs_payload "" 'git -C conf checkout --ours -- f' | CDPATH=$B bash "$HOOK" >/dev/null 2>&1; echo $?)"

# --- 10. no ledger row grants the forced remove of a dirty worktree ----------
# CONVEYOR_MAIN points the hook at a fake checkout whose answered cleanup row lists the edited tree by path.
CL_MAIN=""
gs_add "$OUTSIDE/listed" HEAD; gs_edit "$OUTSIDE/listed"
if [ "$ON" = 1 ]; then
  CL_MAIN=$OUTSIDE/main && mkdir -p "$CL_MAIN/.claude/metrics"
  jq -cn --arg a "Delete them. Paths: $OUTSIDE/listed" '{id: "cleanup-worktrees-with-edits", askedAt: "2026-11-02T12:05:05Z",
    question: "q", proposedDefault: "d", source: "s", answeredAt: "2026-11-02T12:10:08Z", answer: $a}' \
    >"$CL_MAIN/.claude/metrics/decisions.jsonl"
fi
# Bug caught: any agent can write that row with decision.sh, so honouring it lets an agent-writable list delete unsaved work.
check "a dirty worktree listed in an answered cleanup row still blocks" 2 \
  "$([ "$ON" = 1 ] || exit 0; gs_payload "$GS_S" "git worktree remove --force $OUTSIDE/listed" | CONVEYOR_MAIN=$CL_MAIN bash "$HOOK" >/dev/null 2>&1; echo $?)"

# --- 11. the fast lane never pushes, whatever the command sets ---------------------------------------
# Bug caught: the lane's own config (protocol.allow never) is outranked by a command's own override, so
# `GIT_ALLOW_PROTOCOL=file git push --no-verify <path>` from the lane pushed. The lane is the sealed linked worktree,
# found from the session's folder (cwd, or where the hook runs) and the push's -C folders; its branch renamed too.
if [ "$ON" = 1 ]; then
  G worktree add -q -b fast-lane "$B/lane" >/dev/null 2>&1 && G config extensions.worktreeConfig true \
    && git -C "$B/lane" config --worktree protocol.allow never && G worktree add -q -b other "$B/plain" >/dev/null 2>&1
fi
for c in 'git push origin fast-lane' "GIT_ALLOW_PROTOCOL=file git push --no-verify $B/x.git fast-lane" \
  'git -c protocol.allow=always push x' 'cd . && GIT_CONFIG_COUNT=1 git push x'; do
  check "lane_push_blocks: $c, in the lane" 2 "$(gs_in "$B/lane" "$c")"
done
check "lane_push_blocks: -C names the lane" 2 "$(gs_in "$B/repo" "GIT_ALLOW_PROTOCOL=file git -C $B/lane push --no-verify $B/x.git fast-lane")"
check "lane_push_blocks: relative -C dirs into the lane" 2 "$(gs_in "$B/repo" "git -C .. -C lane push x")"
# Bug caught: a -C given as a variable was not followed, so `git -C "$LANE" push` from main passed.
check "lane_push_blocks: -C is a variable" 2 "$(gs_in "$B/repo" 'GIT_ALLOW_PROTOCOL=file git -C "$LANE" push --no-verify "$X" fast-lane')"
check "lane_push_blocks: -C is an unquoted variable, from another worktree" 2 "$(gs_in "$B/plain" 'git -C $LANE push x')"
# Bug caught: only the session's repository was searched, so a literal -C into another repository let a variable reach its lane.
check "lane_push_blocks: a variable -C after a literal -C into a repository with a lane" 2 "$(gs_in "$CF" "git -C $B/repo -C \"\$LANE\" push x fast-lane")"
# Bug caught: a variable stuck to its -C never matched `-C`, so `git -C"$LANE" push` from main passed.
check "lane_push_blocks: a variable stuck to -C" 2 "$(gs_in "$B/repo" 'GIT_ALLOW_PROTOCOL=file git -C"$LANE" push --no-verify "$X" fast-lane')"
# Bug caught: a quoted expression reads as the placeholder QUOTED, which was taken for a folder of that name.
check "lane_push_blocks: -C is a quoted expression with a space" 2 "$(gs_in "$B/repo" 'GIT_ALLOW_PROTOCOL=file git -C "${LANE:-/tmp/fast lane}" push --no-verify "$X" fast-lane')"
check "lane_push_blocks: -C is a backtick substitution" 2 "$(gs_in "$B/repo" 'git -C `echo "$LANE"` push x fast-lane')"
# Bug caught: a variable -C before an absolute one skipped checking the absolute folder, which alone decides.
check "lane_push_blocks: an absolute -C into the lane after a variable -C" 2 "$(gs_in "$CF" "GIT_ALLOW_PROTOCOL=file git -C \"\$PWD\" -C $B/lane push --no-verify x fast-lane")"
# Bug caught: worktree paths were read one a line, so a lane whose folder holds a newline was never found.
if [ "$ON" = 1 ]; then
  git init -q "$B/nl" && git -C "$B/nl" -c user.email=t@t -c user.name=t commit -q --allow-empty -m base \
    && git -C "$B/nl" worktree add -q -b fast-lane "$B/nl/fast"$'\n'lane >/dev/null 2>&1
fi
check "lane_push_blocks: a variable -C, the lane's folder holds a newline" 2 "$(gs_in "$B/nl" 'git -C "$LANE" push x fast-lane')"
check "lane_push_blocks: the session's cwd is the lane" 2 \
  "$([ "$ON" = 1 ] || { echo 2; exit; }; cd "$B/repo" && gs_payload "" 'git push x' | jq -c --arg d "$B/lane" '. + {cwd: $d}' | bash "$HOOK" >/dev/null 2>&1; echo $?)"
[ "$ON" = 1 ] && git -C "$B/lane" branch -q -m renamed
check "lane_push_blocks: the lane's branch renamed" 2 "$(gs_in "$B/lane" "GIT_ALLOW_PROTOCOL=file git push $B/x.git renamed")"
check "lane_push_blocks: other commands in the lane pass" 0 "$(gs_in "$B/lane" 'git branch -m fast-lane')"
check "lane_push_passes: main's checkout pushes" 0 "$(gs_in "$B/repo" "GIT_ALLOW_PROTOCOL=file git push $B/x.git main")"
check "lane_push_passes: another linked worktree pushes" 0 "$(gs_in "$B/plain" 'git push x other')"
# Bug caught: only known repositories were searched, so a variable -C from a repository with no lane reached another's lane.
check "lane_push_blocks: a variable -C into another repository's lane" 2 "$(gs_in "$CF" "LANE=$B/lane; GIT_ALLOW_PROTOCOL=file git -C \"\$LANE\" push --no-verify $B/x.git fast-lane")"
# Bug caught: a -C value named push ended the options, so the variable -C after it was never read.
check "lane_push_blocks: a variable -C after a -C folder named push" 2 "$(gs_in "$CF" "LANE=$B/lane; GIT_ALLOW_PROTOCOL=file git -C push -C \"\$LANE\" push --no-verify $B/x.git fast-lane")"
check "lane_push_passes: an absolute -C out of the lane's repository after a variable -C" 0 "$(gs_in "$B/repo" "git -C \"\$X\" -C $CF push x main")"
check "lane_push_passes: -C out of the lane" 0 "$(gs_in "$B/lane" "git -C $B/repo push x main")"
# Bug caught: the push was judged in the session's folder, so `cd "$LANE" && git push` from main pushed from the lane.
for c in "cd \"$B/lane\" && GIT_ALLOW_PROTOCOL=file git push --no-verify $B/x.git fast-lane" "cd $B; cd lane; git push x" \
  "pushd $B/lane >/dev/null && git push x" "cd -P -- $B/lane && git push x" "(cd $B/repo; true) && cd $B/lane && git push x"; do
  check "lane_push_blocks: $c, from main" 2 "$(gs_in "$B/repo" "$c")"
done
for c in 'cd "$LANE" && git push x' 'cd - && git push x' 'cd $LANE && git -C . push x'; do
  check "lane_push_blocks: $c, a folder the hook cannot tell" 2 "$(gs_in "$B/repo" "$c")"
done
# Bug caught: a cd was taken to replace the folder, but a cd can be skipped, piped, fail, hide behind a redirection, follow
# CDPATH or name a pushd stack index, and each of those pushed from the lane while the hook judged main.
for c in "cd $B/lane && false && cd $B/repo; git push x" "cd $B/lane; cd $B/repo | cat; git push x" \
  "cd $B/lane; cd $B/nonexistent; git push x" ">/dev/null cd $B/lane && git push x" "2>&1 cd $B/lane && git push x" \
  "CDPATH=$B cd lane && git push x" "pushd $B/lane; pushd $B/repo; pushd +1; git push x" "pushd $B/lane; pushd -1; git push x" \
  "(cd $B/lane && git status) && git push x main" "cd>/dev/null $B/lane && GIT_ALLOW_PROTOCOL=file git push --no-verify $B/x.git fast-lane" \
  "cd 2>&1 $B/lane && git push x" "pushd>/dev/null $B/lane && git push x" "cd $B/lane; git push>/dev/null x"; do
  check "lane_push_blocks: $c, from main" 2 "$(gs_in "$B/repo" "$c")"
done
# Bug caught: only a numeric descriptor was read as a redirection, so a named one ({fd}>) hid the cd after it.
for c in "{fd}>/dev/null cd \"$B/lane\" && GIT_ALLOW_PROTOCOL=file git push --no-verify $B/x.git fast-lane" \
  "{fd}> /dev/null cd $B/lane && git push x" "{fd}>&2 cd $B/lane && git push x" "cd {fd}>/dev/null $B/lane && git push x"; do
  check "lane_push_blocks: $c, from main" 2 "$(gs_in "$B/repo" "$c")"
done
check "lane_push_blocks: a cd out of the lane may fail" 2 "$(gs_in "$B/lane" "cd $B/repo; git push x main")"
# Bug caught: a wrapper's option, a HOME the command sets, a folder made by the command itself, or a symlink's logical
# parent each hid the lane, so the push was judged in main.
[ "$ON" = 1 ] && mkdir -p "$B/repo/sub" && ln -s "$B/repo/sub" "$B/lane/link"
for c in "command -p cd $B/lane && git push x" "HOME=$B/lane cd && git push x" "HOME=$B/lane; cd ~ && git push x" \
  "HOME=$B/lane; cd ~/. && git push x" "HOME=$B/lane; git -C ~ push x" "ln -s $B/lane $B/made && cd $B/made && git push x" \
  "cd $B/nonexistent && git push x main" "cd $B/lane/link && cd .. && git push x main"; do
  check "lane_push_blocks: $c, from main" 2 "$(gs_in "$B/repo" "$c")"
done
check "lane_push_passes: a cd into main and up again is not the lane" 0 "$(gs_in "$B/repo" "cd $B/repo/sub && cd .. && git push x main")"
check "lane_push_passes: a cd's 2> redirection is not its folder" 0 "$(gs_in "$B/repo" "cd 2>/dev/null $B/repo/sub && git push x main")"
check "lane_push_passes: pushd -n changes no folder" 0 "$(gs_in "$B/repo" "pushd -n $B/lane >/dev/null; git push x main")"
check "lane_push_passes: cd ./ and ../ stay plain paths" 0 "$(gs_in "$B/repo" "cd ./.git && cd .. && git push x main")"
check "lane_push_passes: a variable cd with no push" 0 "$(gs_in "$B/repo" 'cd "$LANE" && git status && git branch')"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
