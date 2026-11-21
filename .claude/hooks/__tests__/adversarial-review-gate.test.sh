#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Self-test for adversarial-review-gate.sh as a PreToolUse(Bash) hook.
#
# The hook used to screen `git push` from the command TEXT. It could not see
# which refs a push ships, so it hashed local HEAD against origin/main however
# the command was spelled -- and it blocked any command that merely QUOTED a
# push, including the shell one-liners that edit this repo's own hook tests.
# Push enforcement moved to .githooks/pre-push, where the real
# <local sha>/<remote sha> pairs arrive (githooks-pre-push.test.sh covers it).
# What stays here is the one deploy boundary with no git hook behind it:
# deploy.sh.
set -u
# This file's own sed -i, and the hook's sha256sum and xargs -d, are GNU calls: on macOS they run Homebrew's, as
# Conveyor's do (portable.sh).
. "$(dirname "$0")/../../../conveyor/lib/portable.sh"; p_tools

# Pin the base the hook diffs against: a dangling commit whose tree is HEAD's
# plus one runtime file, so the block cases below see a FULL-tier diff that no
# marker can match, whatever origin/main and .claude/review-convergence.json
# say. At push time the marker matches the real outgoing diff and the hook
# rightly permits; without this pin the block cases fail on every real push.
BLOB=$(git hash-object -w --stdin <<<'export const zz = 1;')
TREE=$({ git ls-tree HEAD; printf '100644 blob %s\tzz-review-gate-fixture.ts\n' "$BLOB"; } | git mktree)
REVIEW_GATE_BASE_REF=$(git commit-tree "$TREE" -m 'review-gate self-test base')
export REVIEW_GATE_BASE_REF

HOOK="$(cd "$(dirname "$0")/.." && pwd)/adversarial-review-gate.sh"
HOOK_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
PASS=0 FAIL=0
. "$(dirname "$0")/lib/said.sh" # a FAIL line names the hook inputs of the check (said_in), not only the last call's
CALLS=$(mktemp); trap 'rm -f "$CALLS"' EXIT
check() {
  if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected $2, got $3)$(said)"; fi
  : > "$CALLS"; said_in ''
}
# hook [<mode> <args>]: runs the hook, and notes each call since the last check as one bracket: its arguments or, in hook
# mode (no arguments), the command of the payload it reads, then each setting the gate takes from the environment and
# the folder it runs in. The sandbox, this repository and the pinned base go in as $SANDBOX, $ROOT and $BASE: said.sh
# cuts a note at 600 characters, and the full path of a temporary folder (long on macOS) would push a later call out.
hook() {
  local raw="" v env="" note; [ $# -gt 0 ] || raw=$(cat)
  for v in REVIEW_GATE_BASE_REF CONVEYOR_REVIEW_GATE_BYPASS CLAUDE_PROJECT_DIR; do
    [ -z "${!v+x}" ] || env+=" $v=${!v}"
  done
  note="${*:-<<< $(jq -r '.tool_input.command // .' <<<"$raw" 2>/dev/null || echo "$raw")}$env in $PWD"
  for v in "BASE:${REVIEW_GATE_BASE_REF:-}" "SANDBOX:${SANDBOX:-}" "ROOT:$HOOK_ROOT"; do
    [ -z "${v#*:}" ] || note=${note//"${v#*:}"/\$${v%%:*}}
  done
  printf '[%s] ' "$note" >> "$CALLS"
  said_in "calls $(cat "$CALLS")"
  if [ $# -gt 0 ]; then command bash "$HOOK" "$@" < /dev/null; else command bash "$HOOK" <<<"$raw"; fi
}
cmd() { jq -cn --arg c "$1" '{tool_name:"Bash", tool_input:{command:$c}}'; }
run() { hook >/dev/null 2>&1 <<<"$(cmd "$1")"; echo $?; }

# Case selector: CONVEYOR_SHELL_TEST_CASE=<case>[,<case>] runs only those sections; unset runs all; an unknown name fails.
CASES=" screens blocks wrapped naming unrelated range class writers marker tooling-deploy watermark "
case_on() { [ -z "${CONVEYOR_SHELL_TEST_CASE:-}" ] || [[ ",$CONVEYOR_SHELL_TEST_CASE," == *",$1,"* ]]; }
_sel=${CONVEYOR_SHELL_TEST_CASE:-}; for _c in ${_sel//,/ }; do [[ "$CASES" == *" $_c "* ]] || { echo "FAIL unknown case: $_c (cases:$CASES)"; exit 2; }; done
if case_on screens; then
# --- what it no longer screens ------------------------------------------------
PUSH='git push'
check "a plain push passes"                     0 "$(run "$PUSH origin main")"
check "git -C <path> push passes"               0 "$(run "git -C /repo push origin main")"
check "a quoted push inside another command passes" 0 \
  "$(run "grep -n '$PUSH --force' .githooks/pre-push")"
check "a push after && passes"                  0 "$(run "npm test && $PUSH")"

fi
if case_on blocks; then
# --- what it still blocks -----------------------------------------------------
# Against the pinned base the runtime diff is FULL tier with no marker for it,
# so the deploy entry point must refuse. Both spellings reach the same check.
check "./deploy.sh blocks"                      2 "$(run './deploy.sh dev')"
check "scripts/deploy.sh blocks"                2 "$(run 'bash scripts/deploy.sh dev')"
check "the block names who writes the marker, and no recorder" 0 \
  "$(out=$(hook 2>&1 >/dev/null <<<"$(cmd './deploy.sh dev')"); grep -qF 'written by .githooks/pre-push' <<<"$out" && ! grep -qF 'record-review-convergence' <<<"$out" && echo 0 || echo 1)"
check "the block names the change class"        0 \
  "$(hook 2>&1 >/dev/null <<<"$(cmd './deploy.sh dev')" | grep -qE '^class=(docs|tooling|gate-ci|runtime|cross-file|risky)$' && echo 0 || echo 1)"
check "the exported bypass permits the deploy"  0 \
  "$(CONVEYOR_REVIEW_GATE_BYPASS=1 hook >/dev/null 2>&1 <<<"$(cmd './deploy.sh dev')"; echo $?)"
check "the prefix bypass permits the deploy"    0 \
  "$(run 'CONVEYOR_REVIEW_GATE_BYPASS=1 ./deploy.sh dev')"
# The prefix bypasses ONE command. A second deploy chained after it has to reach
# the gate: the check that looks for it printed a literal `%s` instead of the
# remaining command, so it never matched and the whole line shipped unreviewed.
check "the prefix bypass does not cover a chained second deploy" 2 \
  "$(run 'CONVEYOR_REVIEW_GATE_BYPASS=1 ./deploy.sh dev && ./deploy.sh dev')"
check "the prefix bypass still covers a chained non-deploy" 0 \
  "$(run 'CONVEYOR_REVIEW_GATE_BYPASS=1 ./deploy.sh dev && echo done')"
check "an env-prefixed deploy still blocks"     2 "$(run 'AWS_PROFILE=dev ./deploy.sh dev')"
check "a deploy after && still blocks"          2 "$(run 'npm run build && ./deploy.sh dev')"

fi
if case_on wrapped; then
# --- a wrapped deploy is still a deploy -------------------------------
# A wrapper, an interpreter flag, a shell's -c program and a compound command
# all RUN the script, and each one walked past a check that knew only the bare
# spelling. Every refused shape is paired with the SAME shape running something
# else, so the gate cannot pass by refusing the wrapper itself.
NL=$'\n'
WRAPPED=(
  'nohup ./deploy.sh dev' 'time ./deploy.sh dev' 'time -p ./deploy.sh dev' 'env X=1 ./deploy.sh dev'
  'sh -x ./deploy.sh dev' 'exec ./deploy.sh dev' 'sudo ./deploy.sh dev' 'command ./deploy.sh dev'
  'sudo -u root ./deploy.sh dev' 'env -u AWS_PROFILE ./deploy.sh dev' 'bash -o pipefail ./deploy.sh dev'
  'timeout 900 ./deploy.sh dev' 'nohup env X=1 bash -x scripts/deploy.sh dev' '/usr/bin/env bash ./deploy.sh dev'
  'if true; then ./deploy.sh; fi' '{ ./deploy.sh; }' '(./deploy.sh dev)' 'echo "$(./deploy.sh dev)"'
  "bash -c './deploy.sh dev'" 'bash -c "./deploy.sh dev"' 'bash -c ./deploy.sh' "sh -lc 'cd infra && ./deploy.sh dev'"
  "bash -c 'nohup ./deploy.sh dev'" "bash -c \"sh -c './deploy.sh dev'\"" '"./deploy.sh" dev' './deploy.sh dev >/tmp/out.log'
  "bash -c 'cd infra${NL}./deploy.sh dev'"
  "bash -c 'printf ok'; bash -c './deploy.sh dev'" 'sudo -n ./deploy.sh dev'
)
# Every shape goes to the hook's ACTUAL predicate, extracted by sed: a blocked
# deploy costs a full diff hash, and one per shape put this file at its
# timeout under a parallel run. One shape of each kind then goes end to end.
eval "$(sed -n '/^deploy_invoked()/,/^}/p' "$HOOK")"
. "$(dirname "$HOOK")/lib/strip-quoted.sh"
type deploy_invoked >/dev/null 2>&1 || { echo "FAIL could not extract deploy_invoked from $HOOK"; exit 1; }
for C in "${WRAPPED[@]}"; do check "reads as a deploy: $C" yes "$(deploy_invoked "$C" && echo yes || echo no)"; done
# A quoted program glued to more text is still one word: its token is read by
# its number, never as arithmetic over the whole word.
check "a -c program glued to another word reads cleanly" "" \
  "$(deploy_invoked "bash -c 'printf ok'./deploy.sh" 2>&1 && echo deploy)"
check "a -c deploy glued to its argument is still a deploy" yes \
  "$(deploy_invoked "bash -c './deploy.sh'\" dev\"" 2>/dev/null && echo yes || echo no)"
for C in 'nohup ./deploy.sh dev' 'sudo -u root ./deploy.sh dev' 'if true; then ./deploy.sh; fi' "bash -c './deploy.sh dev'"; do
  check "blocks: $C" 2 "$(run "$C")"
done
NOT_DEPLOY=(
  'nohup printf ok' 'time printf ok' 'time -p printf ok' 'env X=1 printf ok'
  'sh -x ./build.sh dev' 'exec printf ok' 'sudo printf ok' 'command printf ok'
  'sudo -u root printf ok' 'env -u AWS_PROFILE printf ok' 'bash -o pipefail ./build.sh dev'
  'timeout 900 printf ok' 'nohup env X=1 bash -x scripts/build.sh dev' '/usr/bin/env bash ./build.sh dev'
  'if true; then printf ok; fi' '{ printf ok; }' '(printf ok)' 'echo "$(printf ok)"'
  "bash -c 'printf ok'" 'bash -c "printf ok"' 'bash -c ./build.sh' "sh -lc 'cd infra && printf ok'"
  # Naming the script inside a wrapper or a -c program is still not running it.
  "bash -c 'grep -n Release deploy.sh'" 'bash -c "echo ./deploy.sh dev"' "sh -c 'cat ./deploy.sh'"
  'nohup grep -n Release ./deploy.sh' 'time -p cat deploy.sh' 'sudo -u root cat deploy.sh'
  'env -u AWS_PROFILE grep -c dev deploy.sh' 'command -v ./deploy.sh'
  # A -c program belongs to ITS shell: another command's quoted -c value is an
  # argument. And -n only checks the script's syntax.
  "bash -c 'printf ok'; grep -c './deploy.sh' notes.txt" "bash -c 'printf ok' # sh -c './deploy.sh dev'"
  'bash -n ./deploy.sh' 'sh -n scripts/deploy.sh'
  # Comments, quoted prose and a heredoc body are data.
  "printf ok # ./deploy.sh dev" "# nohup ./deploy.sh dev${NL}printf ok"
  'echo "first build; ./deploy.sh dev"' "git commit -m \"bash -c './deploy.sh dev' is gated now\""
  "cat > /tmp/notes.txt <<EOF${NL}./deploy.sh dev${NL}nohup ./deploy.sh dev${NL}EOF"
)
for C in "${NOT_DEPLOY[@]}"; do check "passes: $C" 0 "$(run "$C")"; done
check "the prefix bypass does not cover a chained WRAPPED deploy" 2 \
  "$(run 'CONVEYOR_REVIEW_GATE_BYPASS=1 ./deploy.sh dev && nohup ./deploy.sh dev')"
check "the prefix bypass does not cover a chained -c deploy" 2 \
  "$(run "CONVEYOR_REVIEW_GATE_BYPASS=1 ./deploy.sh dev; bash -c './deploy.sh dev'")"
check "the prefix bypass still covers a chained wrapped non-deploy" 0 \
  "$(run 'CONVEYOR_REVIEW_GATE_BYPASS=1 ./deploy.sh dev && nohup printf ok')"

fi
if case_on naming; then
# --- naming the script is not running it --------------------------------------
# The class this hook is being narrowed out of: it screened for the token
# anywhere in the command, so reading, searching or quoting the script was
# refused as if it shipped code.
check "grepping the script passes"              0 "$(run 'grep -n Release deploy.sh')"
check "grepping the script is SILENT"           "" \
  "$(hook 2>&1 <<<"$(cmd 'grep -n Release deploy.sh')")"
check "reading the script passes"               0 "$(run 'sed -n 1,40p deploy.sh')"
check "quoting the name in a message passes"    0 \
  "$(run 'git commit -m "document the deploy.sh gate"')"

fi
if case_on unrelated; then
# --- an unrelated command costs nothing ---------------------------------------
check "an unrelated command passes"             0 "$(run 'npm run test:guards')"
check "an unrelated command is SILENT"          "" "$(hook 2>&1 <<<"$(cmd 'npm run test:guards')")"

fi
if case_on range; then
# --- the range modes .githooks/pre-push calls ---------------------------------
# One definition of "the runtime diff" is the whole reason pre-push shells out
# to this script instead of hashing a diff of its own.
check "--hash-range prints a sha256"            0 \
  "$(hook --hash-range origin/main HEAD | grep -qE '^([0-9a-f]{64}|EMPTY|NO_BASE)$' && echo 0 || echo 1)"
check "--tier-range prints a tier"              0 \
  "$(hook --tier-range origin/main HEAD | grep -qE '^(FULL|LOW|EMPTY)$' && echo 0 || echo 1)"
check "--hash-range of a ref against itself is EMPTY" "EMPTY" \
  "$(hook --hash-range HEAD HEAD)"
check "--hash-range on an unresolvable base is NO_BASE" "NO_BASE" \
  "$(hook --hash-range no/such/ref HEAD)"
# Bug: a failed check printed only the two values, or only its last call, or lost a call to said.sh's 600-character cut
# when the temporary folder had a long path (macOS). The probe runs four calls in such a folder, then a failing check
# on its own copy of the notes, and its FAIL line must name the first call and the last, with the folder of each.
# The probe unsets CLAUDE_PROJECT_DIR: a Codex card session exports it, and the note would then name it on each call.
check "a failed check names every call it checked, in a folder with a long path" 0 \
  "$( (unset CLAUDE_PROJECT_DIR; CALLS=$(mktemp); SAID_FILE=$CALLS.said; SANDBOX=$(mktemp -d)/$(printf 'long-folder-%.0s' 1 2 3 4 5 6 7 8)
      mkdir -p "$SANDBOX"; cd "$SANDBOX" || exit 1
      hook --hash-range no/such/ref HEAD >/dev/null
      CONVEYOR_REVIEW_GATE_BYPASS=1 hook >/dev/null 2>&1 <<<"$(cmd 'npm test')"
      hook --tier-range HEAD HEAD >/dev/null
      hook --hash-range HEAD HEAD >/dev/null
      check probe x y; rm -rf "${SANDBOX%/*}" "$CALLS" "$SAID_FILE") 2>&1 \
    | grep -qF '[--hash-range no/such/ref HEAD REVIEW_GATE_BASE_REF=$BASE in $SANDBOX] [<<< npm test REVIEW_GATE_BASE_REF=$BASE CONVEYOR_REVIEW_GATE_BYPASS=1 in $SANDBOX] [--tier-range HEAD HEAD REVIEW_GATE_BASE_REF=$BASE in $SANDBOX] [--hash-range HEAD HEAD REVIEW_GATE_BASE_REF=$BASE in $SANDBOX]' && echo 0 || echo 1)"
fi
# --- change class -------------------------------------------------------------
# docs / tooling / runtime / cross-file / risky is what decides how many
# reviewers a diff gets and whether a codex-only marker attests it, so each case
# names exactly the files it classifies. A throwaway repo is the only way to do
# that: this repo's own HEAD carries whatever the unit happens to have changed.
SANDBOX=$(mktemp -d); trap 'rm -rf "$SANDBOX" "$CALLS"' EXIT
# An empty host file folder: the state folder is the sandbox's own, never a live stateDir this host names.
export XDG_CONFIG_HOME="$SANDBOX/config"
build() {  # build <path>[:<content>] ... -- commit 2 adds them on top of commit 1
  rm -rf "$SANDBOX/repo"; mkdir -p "$SANDBOX/repo"
  (
    cd "$SANDBOX/repo" || exit 1
    git init -q . && git config user.email t@t.t && git config user.name t
    echo seed > README.md && git add -A && git commit -qm base
    for spec in "$@"; do
      p=${spec%%:*}; c=${spec#*:}; [ "$c" = "$p" ] && c='export const x = 1;'
      mkdir -p "$(dirname "$p")" && printf '%s\n' "$c" > "$p"
    done
    git add -A && git commit -qm tip
  ) >/dev/null 2>&1
}
class() { ( cd "$SANDBOX/repo" && hook --class-range HEAD~1 HEAD ); }
contract() { ( cd "$SANDBOX/repo" && hook --contract-range HEAD~1 HEAD >/dev/null 2>&1 ); echo $?; }
if case_on class; then

build docs/notes.md
check "a docs-only diff is class docs"                docs       "$(class)"
build scripts/x.sh
check "a scripts-only diff is class tooling"          tooling    "$(class)"
# .claude/ is docs only for its prose: a loop script is code, and read as docs
# the merge reported "docs class has no convergence marker" for one.
build .claude/scripts/x.sh
check "a .claude/scripts-only diff is class tooling"  tooling    "$(class)"
build .claude/rules/x.md
check "a .claude/ prose diff stays class docs"        docs       "$(class)"
build tools/thing.ts
check "a tools-only diff is class tooling"            tooling    "$(class)"
build src/services/__tests__/thing.test.ts
check "a tests-only diff is class tooling"            tooling    "$(class)"
# web/e2e is never shipped: it is outside the app bundle and runs from a dev
# shell, so its non-.spec files (the walkthrough runner) are tooling too.
build web/e2e/walkthrough/run.ts
check "a web/e2e-only diff is class tooling"          tooling    "$(class)"
# Tooling and test files do not count toward "more than one runtime file", so
# one source file keeps its single-reviewer class however many runners and
# tests ride with it.
build web/e2e/walkthrough/run.ts web/src/App.tsx
check "web/e2e plus one web/src file is class runtime" runtime   "$(class)"
build web/src/App.tsx web/src/__tests__/App.test.tsx
check "a source file plus its test is class runtime"  runtime    "$(class)"
build web/src/App.tsx web/src/Panel.tsx web/src/__tests__/App.test.tsx
check "two source files plus a test are cross-file"   cross-file "$(class)"
build web/e2e/walkthrough/lane-guard.test.ts
check "a guard-class test under web/e2e is not tooling" runtime  "$(class)"
# CSS is shipped product, not tooling. It stays a code class; the older LOW
# tier still covers it, which is what keeps a LOW-TIER-GO marker meaningful.
build web/src/a.css
check "a CSS-only diff is not class tooling"          runtime    "$(class)"
# gate/CI is executable policy: a wrong gate blocks every ship or lets a
# runtime diff through, so it keeps a reviewer even though tooling lost one.
build .githooks/pre-commit
check "a githooks diff is class gate-ci"              gate-ci    "$(class)"
build .github/workflows/x.yml
check "a workflow diff is class gate-ci"              gate-ci    "$(class)"
build .claude/hooks/x.sh
check "a claude-hooks diff is class gate-ci"          gate-ci    "$(class)"
# A hook's own TEST runs in no gate, so it is not executable policy: it is a
# test, and a test is not a reviewed class. Four lines
# added to a hook self-test used to demand a Codex round. It lands on docs
# rather than tooling because RUNTIME_PATHSPEC excludes .claude entirely, so
# both file sets are empty -- the same reason a hook-only diff would read as
# prose if gate-ci did not claim it first. Either way nothing is demanded.
build .claude/hooks/__tests__/x.test.sh
check "a hook-test-only diff is not a reviewed class" docs       "$(class)"
# The carve-out is the TEST, never the hook. A guard edited beside its test
# still gets its reviewer, and still binds the marker to that hook's diff.
build .claude/hooks/x.sh .claude/hooks/__tests__/x.test.sh
check "a hook beside its own test is still gate-ci"   gate-ci    "$(class)"
build scripts/x.sh .githooks/pre-commit
check "gate-ci outranks tooling in a mixed diff"      gate-ci    "$(class)"
build .githooks/pre-commit src/services/billing-service.ts
check "risky outranks gate-ci in a mixed diff"        risky      "$(class)"
build src/routes/foo.ts
check "one plain runtime file is class runtime"       runtime    "$(class)"
build src/routes/foo.ts src/routes/bar.ts
check "two runtime files are class cross-file"        cross-file "$(class)"
build src/services/billing-service.ts
check "a money path is class risky"                   risky      "$(class)"
build src/routes/auth/login.ts
check "an auth route is class risky"                  risky      "$(class)"
build src/services/tenant-purge/sweeper.ts
check "a tenant-purge file is class risky"            risky      "$(class)"
build 'src/routes/foo.ts:await transactWrite(items);'
check "a file running a transaction is class risky"   risky      "$(class)"
# Moving a file OFF an atomic write is the change most in need of the expensive
# review, and it is invisible at the tip: the base side of the range is where
# the transaction still is.
build_removal() {  # commit 1 runs a transaction in <path>; commit 2 replaces it
  rm -rf "$SANDBOX/repo"; mkdir -p "$SANDBOX/repo"
  (
    cd "$SANDBOX/repo" || exit 1
    git init -q . && git config user.email t@t.t && git config user.name t
    mkdir -p "$(dirname "$1")"
    printf 'await transactWrite(items);\n' > "$1"
    git add -A && git commit -qm base
    printf 'await putItem(items);\n' > "$1"
    git add -A && git commit -qm tip
  ) >/dev/null 2>&1
}
build_removal src/services/foo.ts
check "removing a transaction is class risky"         risky      "$(class)"
# Deleting the file outright removes the transaction the same way.
build_removal src/services/foo.ts
( cd "$SANDBOX/repo" && git rm -q src/services/foo.ts && git commit -qm delete ) >/dev/null 2>&1
check "deleting a transaction file is class risky"    risky      \
  "$( cd "$SANDBOX/repo" && hook --class-range HEAD~2 HEAD )"
# The record (working-tree) mode reaches the same answer from the staged index.
build_removal src/services/foo.ts
check "removing a transaction is risky when staged"   risky      \
  "$( cd "$SANDBOX/repo" \
      && git reset -q --soft HEAD~1 \
      && REVIEW_GATE_BASE_REF=$(git rev-parse HEAD) hook --class-only )"
# A drift guard is deliberately NOT tooling: weakening one deserves the full loop
# (the same carve-out LOW tier already makes).
build src/config/__tests__/thing.guard.test.ts
check "a drift guard is not class tooling"            runtime    "$(class)"

fi
if case_on writers; then
# --- persisted writers need one test that also names their changed reader --
build \
  'src/repositories/widget-repository.ts:export function writeWidget() {}' \
  'src/services/widget-reader.ts:export function readWidget() {}' \
  'src/repositories/__tests__/widget.test.ts:writeWidget();'
check "a repository writer with a writer-only test is refused" 2 "$(contract)"
check "the refusal names the writer file" 0 \
  "$(cd "$SANDBOX/repo" && hook --contract-range HEAD~1 HEAD 2>&1 | grep -q 'widget-repository.ts' && echo 0 || echo 1)"

build \
  'src/repositories/widget-repository.ts:export function writeWidget() {}' \
  'src/services/widget-reader.ts:export function readWidget() {}' \
  'src/repositories/__tests__/widget.test.ts:writeWidget(); readWidget();'
check "one test naming the changed writer and reader passes" 0 "$(contract)"

build \
  'src/services/widget-writer.ts:export function writeWidget() {}' \
  'src/services/__tests__/widget.test.ts:writeWidget();'
check "a change outside persisted contract paths is untouched" 0 "$(contract)"
# A writer deleted at the tip writes nothing new; no test can name a file that
# is gone (prism-unit-5 lost a ship to this on 2026-09-10).
build 'src/repositories/widget-repository.ts:export function writeWidget() {}'
( cd "$SANDBOX/repo" && git rm -q src/repositories/widget-repository.ts && git commit -qm delete ) >/dev/null 2>&1
check "deleting a repository writer needs no producer-reader test" 0 "$(contract)"
# A comment-only edit in a writer changes no persisted shape (prism-unit-5,
# 2026-09-10: one word in a doc comment asked for a producer-reader test).
build $'src/repositories/widget-repository.ts:// modeled on the old store\nexport function writeWidget() {}'
( cd "$SANDBOX/repo" && printf '// modeled on the platform store\nexport function writeWidget() {}\n' > src/repositories/widget-repository.ts && git commit -qam comment ) >/dev/null 2>&1
check "a comment-only change to a repository writer needs no test" 0 "$(contract)"
build $'src/repositories/widget-repository.ts:// modeled on the old store\nexport function writeWidget() {}'
( cd "$SANDBOX/repo" && printf '// modeled on the old store\nexport function writeWidget(x) {}\n' > src/repositories/widget-repository.ts && git commit -qam code ) >/dev/null 2>&1
check "a code change to a repository writer still needs the test" 2 "$(contract)"
# A second export only counts when it is a reader. An unrelated constant
# beside the writer exercises no read.
WIDGET_REPO=$'src/repositories/widget-repository.ts:export function writeWidget() {}\nexport function readWidget() {}\nexport const VERSION = 1;'
build "$WIDGET_REPO" 'src/repositories/__tests__/widget.test.ts:writeWidget(); VERSION;'
check "a writer test naming an unrelated second export is refused" 2 "$(contract)"
build "$WIDGET_REPO" 'src/repositories/__tests__/widget.test.ts:writeWidget(); readWidget();'
check "a writer test naming the same file's reader passes" 0 "$(contract)"
# The other export must be the writer: a reader plus a constant exercises no write.
build "$WIDGET_REPO" 'src/repositories/__tests__/widget.test.ts:readWidget(); VERSION;'
check "a reader test naming an unrelated second export is refused" 2 "$(contract)"
# The write tokens are read in the changed symbols, not the whole file.
# Commit 2 rewrites one line of a class repository that also writes.
edit_repo() { # <line to replace> <replacement>
  build $'src/repositories/widget-repository.ts:export class WidgetRepository {\n  async getWidget(id) {\n    return this.get(id);\n  }\n  async incrementCount(id) {\n    const key = { id };\n    await this.client.send(new UpdateCommand(key));\n  }\n  async upsertWidget(p) {\n    const seen = p.lastSeen;\n    const setAttr = (k) => {\n      return k;\n    };\n    await this.client.send(new UpdateCommand(setAttr(seen)));\n  }\n  itemFor(id) {\n    return { id, version: 1 };\n  }\n  async storeItem(id) {\n    await this.client.send(new PutCommand(this.itemFor(id)));\n  }\n}'
  ( cd "$SANDBOX/repo" && sed -i "s|$1|$2|" src/repositories/widget-repository.ts && git commit -qam edit ) >/dev/null 2>&1
}
edit_repo 'return this.get(id);' 'return this.get(id, true);'
check "a read-only edit in a writing repository needs no producer test" 0 "$(contract)"
edit_repo 'const key = { id };' 'const key = { id, v: 2 };'
check "an edit inside a write method off its token line still needs the test" 2 "$(contract)"
edit_repo '  async getWidget(id) {' '  async getWidget(id) {\n    await this.client.send(new PutCommand(id));'
check "a write added to a read method needs the test" 2 "$(contract)"
edit_repo 'const seen = p.lastSeen;' 'const seen = p.firstSeen;'
check "an edit above a nested helper in a write method still needs the test" 2 "$(contract)"
edit_repo 'return k;' 'return k.trim();'
check "an edit inside a nested helper of a write method still needs the test" 2 "$(contract)"
edit_repo 'version: 1' 'version: 2'
check "an edit to a helper a write method stores still needs the test" 2 "$(contract)"
# The same split holds for `export async function` modules, the common
# repository form: the reader's body is its own symbol, not the preamble.
edit_async_repo() { # <line to replace> <replacement>
  build $'src/repositories/widget-repository.ts:export async function readWidget() {\n  return 1;\n}\nexport async function writeWidget() {\n  const v = 1;\n  await client.send(new PutCommand({ id: v }));\n}'
  ( cd "$SANDBOX/repo" && sed -i "s|$1|$2|" src/repositories/widget-repository.ts && git commit -qam edit ) >/dev/null 2>&1
}
edit_async_repo 'return 1;' 'return 2;'
check "a read-only edit to an exported async reader needs no producer test" 0 "$(contract)"
edit_async_repo 'const v = 1;' 'const v = 2;'
check "an edit inside an exported async writer still needs the test" 2 "$(contract)"

fi
if case_on marker; then
# --- who a recorded marker authorizes ----------------------------------------
# ONE definition of "may this marker attest this diff", shared by the deploy
# gate and .githooks/pre-push, so the two cannot drift. The callers ask about a
# marker FILE, which can be hand-edited, so the answer re-derives the whole
# rule instead of assuming the recorder's own checks ran.
ok() { hook --converged-ok "$1" "$2"; echo $?; }
check "codex alone attests a gate-ci diff"            0 "$(ok codex gate-ci)"
check "codex alone attests a runtime diff"            0 "$(ok codex runtime)"
# One Codex seat is the outside review at every class,
# so codex alone attests the two upper classes as well. The reviewer that used
# to be demanded here read Claude-written code with a Claude lens.
check "codex alone attests a cross-file diff"         0 "$(ok codex cross-file)"
check "codex alone attests a risky diff"              0 "$(ok codex risky)"
check "codex,claude still attests a risky diff"       0 "$(ok codex,claude risky)"
# Codex reviews every attestable diff, so a marker naming only claude attests
# nothing at any class -- a hand-written one must not buy the second family's
# permission on its own.
check "claude alone does NOT attest a risky diff"     1 "$(ok claude risky)"
check "claude alone does NOT attest a cross-file diff" 1 "$(ok claude cross-file)"
check "claude alone does NOT attest a runtime diff"   1 "$(ok claude runtime)"
check "a substring of codex is not the codex token"   1 "$(ok no-codex,claude cross-file)"
# Neither unreviewed class is attestable by a review seat: both gates skip
# them, so a marker there would record permission nobody asked for.
check "no reviewer set attests a tooling diff"        1 "$(ok codex,claude tooling)"
check "no reviewer set attests a docs diff"           1 "$(ok codex,claude docs)"
# A clean round-1 Codex self-review stands
# in for the outside seat on runtime and tooling only; the classes that keep
# their outside reviewer must refuse a hand-written self-review marker.
check "codex-self-review attests a runtime diff"      0 "$(ok codex-self-review runtime)"
check "codex-self-review attests a tooling diff"      0 "$(ok codex-self-review tooling)"
check "codex-self-review does NOT attest cross-file"  1 "$(ok codex-self-review cross-file)"
check "codex-self-review does NOT attest risky"       1 "$(ok codex-self-review risky)"
check "codex-self-review does NOT attest gate-ci"     1 "$(ok codex-self-review gate-ci)"
check "codex-self-review does NOT attest docs"        1 "$(ok codex-self-review docs)"

fi
if case_on tooling-deploy; then
# --- a tooling diff needs no marker at all ------------------------------------
# Tooling has no runtime
# hash to attest, so the deploy boundary asks for nothing. Every other class still does, and this is
# the one loosening in the split, so both halves get a case.
deploy_in_sandbox() {  # runs the hook against the sandbox's own two commits
  (
    cd "$SANDBOX/repo" || exit 1
    REVIEW_GATE_BASE_REF=$(git rev-parse HEAD~1) hook >/dev/null 2>&1 <<<"$(cmd './deploy.sh dev')"
  )
  echo $?
}
build scripts/x.sh
check "a tooling deploy needs no marker"              0 "$(deploy_in_sandbox)"
# A hook self-test ships under .claude/hooks, so its hash is not EMPTY, yet it
# classes docs and the recorder refuses a docs marker. Both gates skip it.
build .claude/hooks/__tests__/x.test.sh
check "a docs-class hook-test deploy needs no marker" 0 "$(deploy_in_sandbox)"
build .githooks/pre-commit
check "a gate-ci deploy still needs one"              2 "$(deploy_in_sandbox)"
build src/routes/foo.ts
check "a runtime deploy still needs one"              2 "$(deploy_in_sandbox)"
# The pre-push hook's own PARTS-REVIEWED marker: the deploy goes on and shows the
# unreviewed commits, never blocks; a marker for another diff still covers nothing.
parts_marker() {  # <hash>
  mkdir -p "$SANDBOX/repo/.claude"
  jq -n --arg h "$1" '{verdict: "PARTS-REVIEWED", reviewers: "none", contentHash: $h, parts: "lane:def123456,unreviewed:abc123456"}' \
    > "$SANDBOX/repo/.claude/review-convergence.json"
}
parts_deploy() {
  ( cd "$SANDBOX/repo" && CLAUDE_PROJECT_DIR=$PWD REVIEW_GATE_BASE_REF=$(git rev-parse HEAD~1) hook 2>&1 <<<"$(cmd './deploy.sh dev')" )
}
parts_marker "$( cd "$SANDBOX/repo" && hook --hash-range HEAD~1 HEAD )"
check "a PARTS-REVIEWED marker for this diff permits the deploy and shows the unreviewed commits" "0 0" \
  "$(parts_deploy >/dev/null; echo $?) $(parts_deploy | grep -qF 'unreviewed commits: abc123456' && echo 0 || echo 1)"
parts_marker deadbeef
check "a PARTS-REVIEWED marker for another diff still blocks" 2 "$(parts_deploy >/dev/null; echo $?)"
rm -f "$SANDBOX/repo/.claude/review-convergence.json"

fi
if case_on watermark; then
# --- the reviewed watermark ---------------------------
# The base is the newest commit whose every ancestor ahead of origin/main is
# covered (a Fast lane landing, or a docs or tooling diff). Without it one new commit re-opened every reviewed
# change behind it and a one-line fix measured against the whole unpushed range.
watermark() {  # the base the gate resolves in the sandbox
  (
    cd "$SANDBOX/repo" || exit 1
    CLAUDE_PROJECT_DIR=$PWD REVIEW_GATE_BASE_REF= \
      hook --base-only 2>/dev/null
  )
}
# Every commit ahead must be covered, oldest first. origin/main, then MID
# (runtime a.ts), TIP (runtime b.ts); the sandbox works on a branch so main's
# reflog can carry a landing line without moving the checkout.
build src/routes/a.ts
( cd "$SANDBOX/repo" && printf 'export const b = 1;\n' > src/routes/b.ts \
  && git add -A && git commit -qm third && git checkout -qB work \
  && git update-ref refs/remotes/origin/main HEAD~2 ) >/dev/null 2>&1
O=$(cd "$SANDBOX/repo" && git rev-parse HEAD~2)
MID=$(cd "$SANDBOX/repo" && git rev-parse HEAD~1)
TIP=$(cd "$SANDBOX/repo" && git rev-parse HEAD)
land() { ( cd "$SANDBOX/repo" && git update-ref -m "$1" refs/heads/main "$2" ) >/dev/null 2>&1; }
check "with no landing on record the base is origin/main" "origin/main" "$(watermark)"
# Bug: a Fast lane landing reviewed by land's own reviewer still needed a marker, so it could not push.
land "fast-lane: land $MID on $O" "$MID"
check "a fast-lane landing covers its range" "$MID" "$(watermark)"
# Bug: a line without the old main names no reviewed range, so it must cover nothing.
( cd "$SANDBOX/repo" && rm -f .git/logs/refs/heads/main ) >/dev/null 2>&1
land "fast-lane: land $MID" "$O"
check "the old land line shape covers nothing" "origin/main" "$(watermark)"
# Bug: a docs or metrics commit after reviewed work stopped the walk and re-opened it.
land "fast-lane: land $TIP on $O" "$TIP"
( cd "$SANDBOX/repo" && printf 'x\n' > notes.md && git add -A && git commit -qm docs ) >/dev/null 2>&1
DOCS=$(cd "$SANDBOX/repo" && git rev-parse HEAD)
check "a docs commit after reviewed work advances the base" "$DOCS" "$(watermark)"
# Bug: a docs side commit older than origin/main became the base, so a merge
# taking its tree hashed EMPTY while deleting origin/main's auth route.
build src/routes/auth/check.ts
( cd "$SANDBOX/repo" && git update-ref refs/remotes/origin/main HEAD \
  && B=$(git commit-tree "$(git rev-parse HEAD~1^{tree})" -p HEAD~1 -m side) \
  && git reset -q --hard "$(git commit-tree "$(git rev-parse HEAD~1^{tree})" -p HEAD -p "$B" -m merge)" ) >/dev/null 2>&1
check "a side commit never becomes the base" "origin/main" "$(watermark)"

# Conveyor's card records. origin/main, then MID (runtime a.ts), TIP (runtime b.ts), each a landing of its
# own. Bug: the gate knew only the unit marks, so every commit Conveyor landed read as unreviewed.
build src/routes/a.ts
( cd "$SANDBOX/repo" && printf 'export const b = 1;\n' > src/routes/b.ts \
  && git add -A && git commit -qm third && git update-ref refs/remotes/origin/main HEAD~2 ) >/dev/null 2>&1
MID=$(cd "$SANDBOX/repo" && git rev-parse HEAD~1)
TIP=$(cd "$SANDBOX/repo" && git rev-parse HEAD)
landed() {  # <card> <sha> [extra keys as json]: one landed line, the shape conveyor.sh's land writes
  local x=${3:-}; [ -n "$x" ] || x='{}'
  jq -cn --arg c "$1" --arg s "$2" --argjson x "$x" '{card: $c, issue: 7, step: "landed", time: "2026-11-10T00:00:00Z",
    tokens: {claude: 0, codex: 0}, result: "ok", sha: $s, reason: "", product: true} + $x'
}
# The sandbox's main checkout has no conveyor/ at all, as a project on the plugin has none once its own engine is
# deleted: the host file puts its state folder outside it, and the gate asks the engine of the install the hook is
# part of (this checkout's) where that is. Bug: the gate ran the project's own conveyor.sh, so with it deleted every
# Conveyor landing read as unreviewed and every push was refused.
card_base() {  # <card record line>...: the base with those card records
  local d
  rm -rf "$SANDBOX/repo/conveyor" && mkdir -p "$XDG_CONFIG_HOME/conveyor" \
    && jq -n --arg m "$SANDBOX/repo" --arg s "$SANDBOX/state" '{main: $m, stateDir: $s}' > "$XDG_CONFIG_HOME/conveyor/host.json" \
    && d=$(CONVEYOR_MAIN=$SANDBOX/repo command bash "$HOOK_ROOT/conveyor/conveyor.sh" state-dir) \
    && mkdir -p "$d" && printf '%s\n' "$@" > "$d/cards.jsonl" && ! [ -e "$SANDBOX/repo/conveyor" ]
  watermark
}
check "commits Conveyor landed on a GO are reviewed" "$TIP" \
  "$(card_base "$(landed c1-7 "$MID")" "$(landed c2-8 "$TIP")")"
check "a landing under the 3-review rule with its leftovers filed is reviewed" "$TIP" \
  "$(card_base "$(landed c1-7 "$MID" '{"leftover":true,"followups":[12]}')" "$(landed c2-8 "$TIP")")"
check "a commit with no card record stays unreviewed, and stops the walk" "$MID" \
  "$(card_base "$(landed c1-7 "$MID")")"
check "a card landing above a commit with no card record does not cover it" "origin/main" \
  "$(card_base "$(landed c2-8 "$TIP")")"
check "a landing with leftovers and no filed follow-up stays unreviewed" "origin/main" \
  "$(card_base "$(landed c1-7 "$MID" '{"leftover":true,"followups":[]}')" "$(landed c2-8 "$TIP")")"
check "a blocked card and a broken line review nothing" "origin/main" \
  "$(card_base "$(landed c1-7 "$MID" '{"step":"blocked"}')" '{"card":"c1-7","step":"landed","result":"ok","sha":"'"${MID:0:12}"'"}' 'not json')"
check "--conveyor-reviewed prints the commit and its card" "$MID c1-7" \
  "$(card_base "$(landed c1-7 "$MID")" >/dev/null; cd "$SANDBOX/repo" && hook --conveyor-reviewed)"
rm -rf "$SANDBOX/state" "$XDG_CONFIG_HOME/conveyor"
check "no card records at all leaves the base at origin/main" "origin/main" "$(watermark)"

fi
echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
