#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Self-test for dependency-addition-guard.sh. Run directly.
#
# Two tiers, and the manifest tier is the one that changed.
#
#   - What the manifest will SAY after the edit is the question, so the edit is
#     applied to the file on disk and the RESULT's dependency maps are read.
#     Guessing at a fragment's line shapes answered a different question: an
#     engines entry, a script, or any `"key": "value"` in an unrelated section
#     read as a package.
#   - An approved package can now be written into the manifest directly. The
#     install form writes package.json itself, but node_modules in a linked
#     worktree is a symlink to the main checkout's copy, so there was no way to
#     express an approval the hook would accept. The token is an EXACT name, the
#     same shape flag-addition-guard uses.
#
# The command tier is unchanged and pinned here so the manifest cases are not
# passing on a hook that stopped firing.
set -u

HOOK="$(cd "$(dirname "$0")/.." && pwd)/dependency-addition-guard.sh"
PASS=0 FAIL=0
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

MANIFEST="$TMP/package.json"
cat > "$MANIFEST" <<'JSON'
{
  "name": "fixture",
  "version": "1.0.0",
  "scripts": {
    "build": "tsc"
  },
  "engines": {
    "node": ">=24"
  },
  "dependencies": {
    "zod": "^3.22.0"
  },
  "devDependencies": {
    "typescript": "^5.4.0"
  }
}
JSON

# Each hook run since the last check, so a failed check names the payload it checked, not only the two values.
INPUTS="$TMP/inputs"; : > "$INPUTS"
check() {
  local in; in=$(cat "$INPUTS"); : > "$INPUTS"
  if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected $2, got $3; hook input: ${in:-none})"; fi
}
# hook: runs $HOOK on the payload on stdin, and logs the hook's name, any approval and the payload.
hook() {
  local in; in=$(cat)
  printf '[%s%s <<< %s]' "${HOOK##*/}" "${CONVEYOR_DEP_APPROVED+ CONVEYOR_DEP_APPROVED=$CONVEYOR_DEP_APPROVED}" "$in" >> "$INPUTS"
  bash "$HOOK" <<<"$in"
}
# The hook reads the command's directory from the payload's cwd; the fixture
# directory has no node_modules, so only the link cases below see one.
bash_p() { jq -cn --arg c "$1" --arg d "${2:-$TMP}" '{tool_name:"Bash", cwd:$d, tool_input:{command:$c}}'; }
edit()   { jq -cn --arg fp "$1" --arg o "$2" --arg n "$3" '{tool_name:"Edit", tool_input:{file_path:$fp, old_string:$o, new_string:$n}}'; }
write()  { jq -cn --arg fp "$1" --arg c "$2" '{tool_name:"Write", tool_input:{file_path:$fp, content:$c}}'; }
run()    { hook >/dev/null 2>&1 <<<"$1"; echo $?; }
run_env() { ( export "${1?}"; hook >/dev/null 2>&1 <<<"$2" ); echo $?; }
err()    { hook 2>&1 >/dev/null <<<"$1"; }

INSTALL="npm ""install"
ADD="yarn ""add"

# Case selector: CONVEYOR_SHELL_TEST_CASE=<case>[,<case>] runs only those sections; unset runs all; an unknown name fails.
CASES=" command manifest python npm-ci "
case_on() { [ -z "${CONVEYOR_SHELL_TEST_CASE:-}" ] || [[ ",$CONVEYOR_SHELL_TEST_CASE," == *",$1,"* ]]; }
_sel=${CONVEYOR_SHELL_TEST_CASE:-}; for _c in ${_sel//,/ }; do [[ "$CASES" == *" $_c "* ]] || { echo "FAIL unknown case: $_c (cases:$CASES)"; exit 2; }; done
if case_on command; then
# --- the command tier, unchanged ---------------------------------------------
check "installing a package blocks"             2 "$(run "$(bash_p "$INSTALL lodash")")"
check "yarn add blocks"                         2 "$(run "$(bash_p "$ADD lodash")")"
check "a lockfile-driven install passes"        0 "$(run "$(bash_p "npm ci")")"
check "an approved install passes"              0 \
  "$(run "$(bash_p "CONVEYOR_DEP_APPROVED=1 $INSTALL lodash")")"
# Bug: a failed check printed only the two values, never the command, package or approval the hook was given.
check "a failed check names the payload and approval it checked" 0 \
  "$( (run_env CONVEYOR_DEP_APPROVED=lodas "$(bash_p "$INSTALL lodash")" >/dev/null
      cp "$INPUTS" "$TMP/probe.in"; INPUTS=$TMP/probe.in; check probe x y) \
    | grep -qF "(expected x, got y; hook input: [dependency-addition-guard.sh CONVEYOR_DEP_APPROVED=lodas <<< $(bash_p "$INSTALL lodash")])" && echo 0 || echo 1)"
# The name trim, run under the system awk with owner_approved stubbed to print each name. Bug: a cut list holding
# "[=" is an equivalence class to gawk, which prints "invalid collating element" and trims nothing.
eval "$(sed -n '/^cmd_approved() {/,/^}/p' "$HOOK")"
owner_approved() { printf '%s ' "$1"; }
check "the name trim cuts a pip spec at = [ > ; with no awk error" "pkg pkg pkg pkg ||" \
  "$(cmd_approved "pip install pkg==1.0 pkg[extra] pkg>=2 pkg;python_version" 2>&1)||"
check "and at ] < ! ~" "a b c d ||" "$(cmd_approved "pip install a]x b<1 c!=2 d~=3" 2>&1)||"
# The system awk may be mawk, which accepts "[="; gawk and busybox awk refuse it as gawk does, so run under them too.
for A in gawk "busybox awk"; do
  command -v "${A%% *}" >/dev/null || continue
  check "the name trim under $A" "pkg pkg pkg a b ||" \
    "$(awk() { $A "$@"; }; cmd_approved "pip install pkg==1.0 pkg[extra] pkg>=2 a]x b~=3" 2>&1)||"
done
check "a second install after an approved one blocks" 2 \
  "$(run "$(bash_p "CONVEYOR_DEP_APPROVED=1 $INSTALL lodash && $INSTALL sneaky")")"

fi
if case_on manifest; then
# --- the manifest tier: the maps, not the line shapes -------------------------
DEPS_OLD='"dependencies": {
    "zod": "^3.22.0"'
check "adding a dependency blocks"              2 \
  "$(run "$(edit "$MANIFEST" "$DEPS_OLD" '"dependencies": {
    "lodash": "^4.17.21",
    "zod": "^3.22.0"')")"
check "the block names the package"             0 \
  "$(err "$(edit "$MANIFEST" "$DEPS_OLD" '"dependencies": {
    "lodash": "^4.17.21",
    "zod": "^3.22.0"')" | grep -qF "'lodash'" && echo 0 || echo 1)"
check "adding a devDependency blocks"           2 \
  "$(run "$(edit "$MANIFEST" '"typescript": "^5.4.0"' '"typescript": "^5.4.0",
    "vitest": "^2.0.0"')")"
check "bumping an existing dependency passes"   0 \
  "$(run "$(edit "$MANIFEST" '"zod": "^3.22.0"' '"zod": "^3.25.0"')")"
check "a version bump is SILENT"                "" \
  "$(hook 2>&1 <<<"$(edit "$MANIFEST" '"zod": "^3.22.0"' '"zod": "^3.25.0"')")"
check "removing a dependency passes"            0 \
  "$(run "$(edit "$MANIFEST" '  "devDependencies": {
    "typescript": "^5.4.0"
  }
' '')")"

# The false-positive class the line-shape scan produced: any `"key": "value"`
# pair outside a dependency map read as a package.
check "a new script is not a package"           0 \
  "$(run "$(edit "$MANIFEST" '"build": "tsc"' '"build": "tsc",
    "lint": "eslint"')")"
check "a new engines entry is not a package"    0 \
  "$(run "$(edit "$MANIFEST" '"node": ">=24"' '"node": ">=24",
    "npm": ">=10"')")"
check "a new top-level field is not a package"  0 \
  "$(run "$(edit "$MANIFEST" '"name": "fixture"' '"name": "fixture",
  "license": "UNLICENSED"')")"
check "a script addition is SILENT"             "" \
  "$(hook 2>&1 <<<"$(edit "$MANIFEST" '"build": "tsc"' '"build": "tsc",
    "lint": "eslint"')")"

# A manifest the guard cannot parse is blocked plainly, never judged by
# line shapes: those named the edit's own text as a new package.
check "an edit that leaves package.json unparsable blocks and says so" 0 \
  "$(err "$(edit "$MANIFEST" '"build": "tsc"' '"build": "tsc",,')" | grep -qF 'would leave' && echo 0 || echo 1)"
check "an unparsable result is not called an added package" 0 \
  "$(err "$(edit "$MANIFEST" '"build": "tsc"' '"build": "tsc",,')" | grep -qF 'requires the owner' && echo 1 || echo 0)"
BROKEN="$TMP/broken-pkg/package.json"
mkdir -p "$TMP/broken-pkg"
printf '{"name":"b","dependencies":{"zod":"^3.22.0",}}\n' >"$BROKEN"
check "an edit over an unparsable package.json blocks" 2 \
  "$(run "$(edit "$BROKEN" '"zod": "^3.22.0"' '"zod": "^3.25.0"')")"
check "an edit over an unparsable package.json names the repair" 0 \
  "$(err "$(edit "$BROKEN" '"zod": "^3.22.0"' '"zod": "^3.25.0"')" | grep -qF 'git show HEAD:' && echo 0 || echo 1)"
check "a rewrite over an unparsable package.json blocks" 2 \
  "$(run "$(write "$BROKEN" '{"name":"b","dependencies":{"zod":"^3.22.0"}}')")"

# --- approval, expressible without an install ---------------------------------
ADD_LODASH=$(edit "$MANIFEST" "$DEPS_OLD" '"dependencies": {
    "lodash": "^4.17.21",
    "zod": "^3.22.0"')
check "an approved package may be written in"   0 \
  "$(run_env CONVEYOR_DEP_APPROVED=lodash "$ADD_LODASH")"
check "an approved write is SILENT"             "" \
  "$(CONVEYOR_DEP_APPROVED=lodash hook 2>&1 <<<"$ADD_LODASH")"
check "approval is exact, not a prefix"         2 \
  "$(run_env CONVEYOR_DEP_APPROVED=lodas "$ADD_LODASH")"
check "approving a different package does not help" 2 \
  "$(run_env CONVEYOR_DEP_APPROVED=ramda "$ADD_LODASH")"
check "several approvals are comma-separated"   0 \
  "$(run_env CONVEYOR_DEP_APPROVED=ramda,lodash "$ADD_LODASH")"
check "an unapproved package alongside an approved one blocks" 2 \
  "$(run_env CONVEYOR_DEP_APPROVED=lodash "$(edit "$MANIFEST" "$DEPS_OLD" '"dependencies": {
    "lodash": "^4.17.21",
    "sneaky": "^1.0.0",
    "zod": "^3.22.0"')")"
check "the block names the env form"            0 \
  "$(err "$ADD_LODASH" | grep -qF 'CONVEYOR_DEP_APPROVED=lodash' && echo 0 || echo 1)"
DEFER_LINE='record it as a main-only deferred item (one line under ## Main-only (deferred) in the evidence file) and go on without it; do not ask main.'
check "the block says record and go on (manifest edit)" 1 "$(err "$ADD_LODASH" | grep -cF "If you need this package, $DEFER_LINE")"
check "the block says record and go on (install command)" 1 "$(err "$(bash_p "$INSTALL lodash")" | grep -cF "If you need this package, $DEFER_LINE")"

# --- the other payload shapes -------------------------------------------------
FULL=$(cat "$MANIFEST")
check "a full-file Write of the same manifest passes" 0 "$(run "$(write "$MANIFEST" "$FULL")")"
check "a Write that adds a dependency blocks"   2 \
  "$(run "$(write "$MANIFEST" "${FULL/\"zod\": \"^3.22.0\"/\"lodash\": \"^4.17.21\",
    \"zod\": \"^3.22.0\"}")")"
check "a MultiEdit adding a dep in a later hunk blocks" 2 \
  "$(run "$(jq -cn --arg fp "$MANIFEST" '{tool_name:"MultiEdit", tool_input:{file_path:$fp, edits:[
    {old_string:"\"build\": \"tsc\"", new_string:"\"build\": \"tsc --noEmit\""},
    {old_string:"\"zod\": \"^3.22.0\"", new_string:"\"lodash\": \"^4.17.21\",\n    \"zod\": \"^3.22.0\""}]}}')")"

# A brand-new manifest is a new dependency surface in itself.
check "a NEW package.json with a dependency blocks" 2 \
  "$(run "$(write "$TMP/sub/package.json" '{"name":"sub","dependencies":{"lodash":"^4.17.21"}}')")"
check "a NEW package.json with no dependency passes" 0 \
  "$(run "$(write "$TMP/sub/package.json" '{"name":"sub","scripts":{"build":"tsc"}}')")"
check "an approved package in a NEW package.json passes" 0 \
  "$(run_env CONVEYOR_DEP_APPROVED=lodash "$(write "$TMP/sub/package.json" '{"name":"sub","dependencies":{"lodash":"^4.17.21"}}')")"

fi
if case_on python; then
# --- Python manifests and installers -----------------------------------
ROOT=$(git rev-parse --show-toplevel)
PIP="pip ""install"; PIP3="pip3 ""install"; UVADD="uv ""add"
check "pip install blocks"                      2 "$(run "$(bash_p "$PIP requests")")"
check "pip3 install blocks"                     2 "$(run "$(bash_p "$PIP3 requests")")"
check "uv add blocks"                           2 "$(run "$(bash_p "$UVADD requests")")"
check "a pip install after && blocks"           2 "$(run "$(bash_p "cd ml/prism && $PIP -U requests")")"
check "pip install -r <requirements> passes"    0 "$(run "$(bash_p "$PIP -r ml/prism/requirements.txt")")"
check "pip install -r <requirements> && pytest passes" 0 "$(run "$(bash_p "$PIP -r ml/prism/requirements.txt && pytest")")"
check "pip install -r plus a package blocks"   2 "$(run "$(bash_p "$PIP -r requirements.txt requests")")"
check "an approved pip install passes"          0 "$(run "$(bash_p "CONVEYOR_DEP_APPROVED=1 $PIP requests")")"
for m in lambdas/barcode/requirements.txt ml/prism/requirements.txt; do
  check "a new line in $m blocks"               2 "$(run "$(edit "$ROOT/$m" '' $'\nzz-not-a-dep==2.0\n')")"
done
PYPROJECT="$TMP/py/pyproject.toml"
mkdir -p "$TMP/py" && printf '[project]\nname = "fixture"\nversion = "0.2.0"\ndependencies = ["httpx>=0.25.0"]\n' > "$PYPROJECT"
check "a new pyproject dependency blocks"       2 \
  "$(run "$(edit "$PYPROJECT" 'dependencies = ["httpx>=0.25.0"]' 'dependencies = ["httpx>=0.25.0", "requests>=2"]')")"
check "the pyproject block names the package"   0 \
  "$(err "$(edit "$PYPROJECT" 'dependencies = ["httpx>=0.25.0"]' 'dependencies = ["httpx>=0.25.0", "requests>=2"]')" | grep -qF "'requests'" && echo 0 || echo 1)"
check "bumping a pyproject dependency passes"   0 \
  "$(run "$(edit "$PYPROJECT" 'httpx>=0.25.0' 'httpx>=0.27.0')")"
check "a pyproject metadata edit passes"        0 \
  "$(run "$(edit "$PYPROJECT" 'version = "0.2.0"' 'version = "99.0.0"')")"
REQ="$TMP/requirements-dev.txt"
printf '# tools\nnumpy==1.26.0\nPillow>=10\n' > "$REQ"
check "bumping a requirement passes"            0 "$(run "$(edit "$REQ" 'numpy==1.26.0' 'numpy==2.0.0')")"
check "a comment line in requirements passes"   0 "$(run "$(edit "$REQ" '# tools' $'# tools\n# pinned for the box')")"
check "a requirement differing only in case passes" 0 "$(run "$(edit "$REQ" 'Pillow>=10' 'pillow>=11')")"
check "a new requirement blocks"                2 "$(run "$(edit "$REQ" 'Pillow>=10' $'Pillow>=10\nrequests==2.0')")"
check "an approved requirement passes"          0 \
  "$(run_env CONVEYOR_DEP_APPROVED=requests "$(edit "$REQ" 'Pillow>=10' $'Pillow>=10\nrequests==2.0')")"
check "a NEW requirements file with a package blocks" 2 "$(run "$(write "$TMP/py/requirements.txt" 'requests==2.0')")"

check "a file that is not a manifest passes"    0 "$(run "$(edit "$TMP/notes.md" 'a' '"lodash": "^4.17.21"')")"
check "malformed JSON passes rather than wedging" 0 "$(run 'not json')"

fi
if case_on npm-ci; then
# --- npm ci through a worker's shared node_modules link -----------------------
# A worker worktree's node_modules is a symlink to the main checkout's copy;
# npm ci there replaced the link and wiped the shared tree for every worktree.
WTX=$TMP/wt
mkdir -p "$TMP/shared/root-modules" "$TMP/shared/web-modules" "$WTX/web" "$WTX/infra/node_modules" "$TMP/broken"
ln -s "$TMP/shared/root-modules" "$WTX/node_modules"
ln -s "$TMP/shared/web-modules" "$WTX/web/node_modules"
ln -s "$TMP/shared/gone" "$TMP/broken/node_modules"
check "message_naming_npm_ci_passes: a comment, a decision or a search that only names the install is text; a chained real install blocks" "0 0 0 2" \
  "$(for c in "gh issue comment 1 --body 'run npm ci in the main checkout'" "bash .claude/scripts/decision.sh answer d1 'main runs npm ci'" \
    "rg -n 'npm ci' docs" "bash .claude/scripts/decision.sh answer d1 'x'; npm ci"; do run "$(bash_p "$c" "$WTX")"; done | paste -sd' ' -)"
check "npm ci through a linked node_modules blocks" 2 "$(run "$(bash_p "npm ci" "$WTX")")"
check "approval cannot carry npm ci through a link" 2 "$(run "$(bash_p "CONVEYOR_DEP_APPROVED=1 npm ci" "$WTX")")"
check "cd web && npm ci through web's link blocks" 2 "$(run "$(bash_p "cd web && npm ci" "$WTX")")"
check "npm --prefix web ci blocks" 2 "$(run "$(bash_p "npm --prefix web ci" "$WTX")")"
check "npm ci --prefix web blocks" 2 "$(run "$(bash_p "npm ci --prefix web" "$WTX")")"
check "npm ci from inside web blocks" 2 "$(run "$(bash_p "npm ci" "$WTX/web")")"
check "npm ci onto a broken link blocks" 2 "$(run "$(bash_p "npm ci" "$TMP/broken")")"
check "npm ci into infra's real node_modules passes from inside infra" 0 "$(run "$(bash_p "npm ci" "$WTX/infra")")"
check "npm --prefix infra ci passes" 0 "$(run "$(bash_p "npm --prefix infra ci" "$WTX")")"
check "the refusal names the link's target" 1 "$(err "$(bash_p "npm ci" "$WTX")" | grep -c "$TMP/shared/root-modules")"
check "a refused command leaves the link in place" "$TMP/shared/root-modules" "$(readlink "$WTX/node_modules")"
# Every npm ci on the line is checked in ITS OWN folder. One
# folder was taken for the whole line, so a first `npm ci` at the linked root
# ran behind a second one aimed at a real folder; a quoted folder was looked up
# with its quotes on.
ci_blocks() { for C in "$@"; do check "npm ci blocks: $C" 2 "$(run "$(bash_p "$C" "$WTX")")"; done; }
ci_passes() { for C in "$@"; do check "npm ci passes: $C" 0 "$(run "$(bash_p "$C" "$WTX")")"; done; }
ci_blocks 'npm ci && npm --prefix infra ci' 'npm --prefix infra ci && npm ci' 'npm --prefix infra ci; npm ci' \
  'cd "web" && npm ci' "cd 'web' && npm ci" 'npm --prefix "web" ci' 'npm --prefix=web ci' \
  'cd infra && npm ci && cd ../web && npm ci' 'cd infra && npm ci; cd .. && npm ci' '(cd infra && npm ci) && npm ci' \
  'cd infra || npm ci' 'cd infra & npm ci' 'cd infra | npm ci' 'cd web; npm ci' 'pushd web && npm ci' \
  'cd infra && npm --prefix ../web ci' 'cd infra && npm --prefix .. ci' "$(printf 'cd infra\nnpm ci\ncd ..\nnpm ci')" \
  'echo "$(cd web && npm ci)"' 'FOO=1 npm ci' \
  'cd no-such-folder; npm ci' "$(printf 'cd no-such-folder\nnpm ci')" 'cd infra; cd no-such-folder; npm --prefix .. ci'
# The guard does not follow the shell's folder moves (ruling 8): which `cd` took
# effect depends on `&&`, `||`, `;`, subshells and exit codes, and each shape it
# guessed wrong let an install through at the linked root. An npm ci is judged in
# EVERY folder the line could be in, the starting one and each cd/pushd target
# that exists, and passes only when none of them holds a link.
ci_blocks 'cd no-such-folder && echo skipped; npm ci' 'cd no-such-folder || npm ci' '(cd infra); npm ci' \
  'cd infra && false; npm ci' 'if true; then cd web; fi; npm --prefix . ci' 'cd no-such-folder && npm ci' \
  'cd infra && npm ci' 'cd "infra" && npm ci' "cd 'infra' && npm ci" 'cd web && cd ../infra && npm ci' 'cd infra; npm ci' '(cd infra && npm ci) && git status' "$(printf 'cd infra\nnpm ci')"
# A folder the guard cannot read could be the linked one, so it blocks.
ci_blocks 'cd "$SOMEWHERE" && npm ci' 'cd "$(git rev-parse --show-toplevel)" && npm ci' 'npm --prefix "$SOMEWHERE" ci' 'cd `pwd`/infra && npm ci'
check "the refusal for a move it cannot follow says the way out" 1 \
  "$(err "$(bash_p "cd infra && npm ci" "$WTX")" | grep -c 'Run it from the folder itself, or name the folder: npm --prefix <folder> ci')"
ci_passes 'npm --prefix infra ci' 'npm --prefix "infra" ci && git status' 'cd web && npm --prefix ../infra ci' \
  "npm --prefix '$WTX/infra' ci" 'cd web && git status && npm --version' 'cd web && npm run build'
# Run from the folder itself, every folder on the line is a real one.
mkdir -p "$WTX/infra/sub/node_modules"
for C in 'npm ci' 'cd sub && npm ci' 'cd sub || npm ci' '(cd sub && npm ci); npm ci' "cd 'sub' && npm ci"; do
  check "npm ci passes from inside infra: $C" 0 "$(run "$(bash_p "$C" "$WTX/infra")")"
done
# Where `cd -` and `popd` go was set by an earlier command, and an option or a
# pattern is not a folder name the guard can look up: each blocks, even from a
# folder whose own modules are real.
for C in 'cd - && npm ci' 'popd && npm ci' 'pushd +1 && npm ci' 'cd -P sub && npm ci' 'cd su* && npm ci' 'cd {sub,..} && npm ci' 'npm --prefix su? ci'; do
  check "npm ci blocks from inside infra: $C" 2 "$(run "$(bash_p "$C" "$WTX/infra")")"
done

# A replace-all edit is applied to EVERY occurrence. Applied to the first
# only, the rename below changed the script name and left the dependency map as
# it was, so the new package it writes there was never seen.
mkdir -p "$TMP/ra"; RA="$TMP/ra/package.json"
printf '{\n  "scripts": {\n    "jest": "jest"\n  },\n  "devDependencies": {\n    "jest": "^29.0.0",\n    "ts-jest": "^29.0.0"\n  }\n}\n' > "$RA"
edit_all() { jq -cn --arg fp "$1" --arg o "$2" --arg n "$3" '{tool_name:"Edit", tool_input:{file_path:$fp, old_string:$o, new_string:$n, replace_all:true}}'; }
check "a replace-all rename of a repeated key into a new package blocks" 2 "$(run "$(edit_all "$RA" '"jest":' '"vitest":')")"
check "the refusal names the package the rename adds" 1 "$(hook 2>&1 >/dev/null <<<"$(edit_all "$RA" '"jest":' '"vitest":')" | grep -c "'vitest'")"
check "a replace-all edit that adds no name passes" 0 "$(run "$(edit_all "$RA" '"^29.0.0"' '"^30.0.0"')")"
# Old text that is in the file twice cannot be placed: a Codex hunk goes where
# its anchor says, which this hook never sees, so reading it as the FIRST match
# passed a rename that really landed in the dependency map. Claude's own Edit
# refuses such an edit anyway.
check "a rename whose old text is in the file twice blocks without replace-all" 2 "$(run "$(edit "$RA" '"jest":' '"vitest":')")"
check "and the refusal says the text is there more than once" 1 "$(hook 2>&1 >/dev/null <<<"$(edit "$RA" '"jest":' '"vitest":')" | grep -c 'more than once')"
check "the same rename with enough of its line to be the only match passes" 0 "$(run "$(edit "$RA" '"jest": "jest"' '"vitest": "jest"')")"
# The shape a two-hunk Codex patch arrives in: the second hunk's text is in the
# script map and the dependency map alike.
mkdir -p "$TMP/tw"; printf '{\n  "name": "a",\n  "scripts": {\n    "left-pad": "1.3.0"\n  },\n  "dependencies": {\n    "left-pad": "1.3.0"\n  }\n}\n' > "$TMP/tw/package.json"
check "a two-edit change whose second edit could land in either map blocks" 2 "$(run "$(jq -cn --arg fp "$TMP/tw/package.json" \
  '{tool_name:"MultiEdit", tool_input:{file_path:$fp, edits:[{old_string:"\"name\": \"a\"", new_string:"\"name\": \"b\""}, {old_string:"\"left-pad\": \"1.3.0\"", new_string:"\"is-odd\": \"1.3.0\""}]}}')")"
printf '# was flask==1.0 before\nflask==1.0\nrequests==2.0\n' > "$TMP/requirements-twice.txt"
check "a requirements edit whose old text is in the file twice blocks" 2 "$(run "$(edit "$TMP/requirements-twice.txt" 'flask==1.0' 'requests==2.0')")"

# A bare URL requirement counts whole, as an option line does. Every one
# read as the name `https`, so a second URL to a different package was not new.
URLREQ="$TMP/requirements-url.txt"
printf 'https://a.example/one-1.0-py3-none-any.whl\nrequests==2.0\n' > "$URLREQ"
check "a second URL requirement blocks" 2 \
  "$(run "$(edit "$URLREQ" 'requests==2.0' $'requests==2.0\nhttps://b.example/two-2.0-py3-none-any.whl')")"
check "a VCS URL requirement blocks" 2 \
  "$(run "$(edit "$URLREQ" 'requests==2.0' $'requests==2.0\ngit+https://b.example/two.git@v2')")"
check "the refusal names the URL" 1 \
  "$(hook 2>&1 >/dev/null <<<"$(edit "$URLREQ" 'requests==2.0' $'requests==2.0\nhttps://b.example/two-2.0-py3-none-any.whl')" | grep -c "('https://b.example/two-2.0-py3-none-any.whl'")"
check "another line of a manifest that holds a URL requirement still edits" 0 "$(run "$(edit "$URLREQ" 'requests==2.0' 'requests==2.1')")"
check "a named URL requirement is still read by its name" 0 \
  "$(run "$(edit "$URLREQ" 'requests==2.0' 'requests @ https://a.example/requests-2.1.whl')")"

# A bare install is lockfile-driven whatever follows it, and a flag's
# value is not a package. `npm install && git status` and `npm install --prefix
# web` blocked; `npm --prefix web i lodash` ran.
for C in "$INSTALL && git status" "$INSTALL; git status" "$INSTALL | tee /tmp/log" "$INSTALL || true" "($INSTALL)" \
  "$INSTALL --prefix web" "$INSTALL --prefix=web" "npm --prefix web install" "npm i --prefix web && npm run build" \
  "$INSTALL --workspace web" "$INSTALL -w web" "$INSTALL --loglevel error" "$INSTALL --registry https://r.example --prefix web" \
  "$INSTALL 2>&1 | tail -5" "$INSTALL > /tmp/log 2>&1" "$INSTALL >/tmp/log" "pip install -r requirements.txt 2>&1 | tail -5"; do
  check "passes: $C" 0 "$(run "$(bash_p "$C")")"
done
for C in "npm --prefix web i lodash" "$INSTALL --prefix web lodash" "$INSTALL lodash --prefix web" "npm --prefix web install lodash" \
  "$INSTALL --workspace web lodash" "$INSTALL && $INSTALL lodash" "$INSTALL --prefix web; $ADD lodash" "yarn --cwd web add lodash" \
  "$INSTALL lodash 2>&1" "$INSTALL > /tmp/log lodash" "pnpm add -w lodash" "pip install requests 2>&1"; do
  check "blocks: $C" 2 "$(run "$(bash_p "$C")")"
done

# Where a Codex hunk lands. Tried on Codex's own patch tool (0.162.1): a
# hunk with repeated context goes after its `@@` anchor, which this hook never
# sees, and a hunk with no context goes to the END of the file whatever its
# anchor says. So repeated context is refused, never guessed, and an edit with
# no old text is read at the end of the file.
PYT=$TMP/py; mkdir -p "$PYT"
printf '[project]\nname = "x"\ndependencies = [\n  "httpx>=0.25",\n]\n\n[tool.other]\nextras = [\n  "httpx>=0.25",\n]\n' > "$PYT/pyproject.toml"
check "a pyproject hunk whose context is under [project] and a later table blocks" 2 \
  "$(run "$(edit "$PYT/pyproject.toml" $'  "httpx>=0.25",\n]' $'  "httpx>=0.25",\n  "requests>=2",\n]')")"
check "and the refusal says the text is there more than once" 1 \
  "$(err "$(edit "$PYT/pyproject.toml" $'  "httpx>=0.25",\n]' $'  "httpx>=0.25",\n  "requests>=2",\n]')" | grep -c 'more than once')"
check "the same hunk with its table header, so it matches once, is read: a new name blocks" 1 \
  "$(err "$(edit "$PYT/pyproject.toml" $'dependencies = [\n  "httpx>=0.25",\n]' $'dependencies = [\n  "httpx>=0.25",\n  "requests>=2",\n]')" | grep -c "'requests'")"
check "a hunk with no context is read at the end of the file: a list item there is no manifest, and blocks" 2 \
  "$(run "$(edit "$PYT/pyproject.toml" '' $'  "requests>=2",\n')")"
check "a key added with no context lands in the last table, as Codex writes it, and is no dependency" 0 \
  "$(run "$(edit "$PYT/pyproject.toml" '' $'note = "x"\n')")"
check "a new table of dependencies added with no context blocks" 2 \
  "$(run "$(edit "$PYT/pyproject.toml" '' $'\n[dependency-groups]\ndev = ["requests>=2"]\n')")"

# The quoted text of a sender (gh, git, echo, printf, cat) is a message,
# not a command, when every command on the line is one. An issue body that
# DESCRIBED an install was blocked. Run from the linked root, so the npm ci each
# one names would block if it were read.
for C in "gh issue create --title t --body \"the guard refuses bash -c 'cd web && $INSTALL lodash' and sh -c 'npm ci'\"" \
  "git commit -m '$INSTALL lodash is refused; so is pip install requests'" \
  "gh issue create --body \"$(printf 'first line\n%s lodash\nnpm ci\n%s lodash' "$INSTALL" "$ADD")\"" \
  "$(printf "gh issue create --body-file - <<'EOF'\n%s lodash\ncd web && npm ci\nEOF" "$INSTALL")" \
  "echo 'pnpm add lodash' && git status"; do
  check "a message that names an install passes: $C" 0 "$(run "$(bash_p "$C" "$WTX")")"
done
# Any command that is no sender has the whole line read as code: a shell's -c
# string, eval, a shell's standard input, a remote command, a variable or
# substitution run as the command, and anything in backticks. An install after
# the message still counts.
for C in "bash -c '$INSTALL lodash'" "sh -c \"cd web && $INSTALL lodash\"" "/bin/zsh -c '$ADD lodash'" "sudo sh -c '$INSTALL lodash'" \
  "\"bash\" -c '$INSTALL lodash'" "eval \"$INSTALL lodash\"" "$(printf 'bash <<EOF\n%s lodash\nEOF' "$INSTALL")" "bash <<< \"$INSTALL lodash\"" \
  "echo \"$INSTALL lodash\" | sh" "echo lodash | xargs -I{} sh -c \"$INSTALL {}\"" "echo \"$INSTALL lodash\" | xargs -I{} {}" \
  "ssh box \"$INSTALL lodash\"" "C=\"$INSTALL lodash\"; \$C" "echo \"\$($INSTALL lodash)\"" "echo \"\`$INSTALL lodash\`\"" \
  "\"npm\" install lodash" "npm 'install' 'lodash'" "$INSTALL \"lodash\"" "pip install \"requests>=2,<3\"" "$INSTALL \"lodash express\"" \
  "gh issue create --body \"about npm ci\" && $INSTALL lodash" "git commit -m 'note' ; $ADD lodash"; do
  check "a real install still blocks: $C" 2 "$(run "$(bash_p "$C")")"
done
ci_blocks "bash -c 'cd web && npm ci'" "sh -c 'npm ci'" "echo 'cd web && npm ci' | bash" "git commit -m 'npm ci note' && npm ci" '"npm" ci'
# A sender piped or chained to anything that is no sender is read whole: the
# text may be fed to it, and nobody has to list how.
for C in "echo '$INSTALL lodash' | bash" "echo '$INSTALL lodash' | sh" "printf '%s\\n' '$INSTALL lodash' | sudo bash" \
  "echo '$INSTALL lodash' ; make" "echo '$INSTALL lodash' && ./run.sh" "$(printf "echo '%s lodash'\nmake" "$INSTALL")" \
  "echo '$INSTALL lodash' > /tmp/x.sh; bash /tmp/x.sh" "echo '$INSTALL lodash' > >(bash)" "A=1 echo '$INSTALL lodash'" \
  "gh issue create --body '$INSTALL lodash' | tee /tmp/out" "git rebase --exec '$INSTALL lodash' main" \
  "/usr/bin/echo '$INSTALL lodash'" "if true; then echo '$INSTALL lodash'; fi"; do
  check "a sender beside a command that is no sender is read whole: $C" 2 "$(run "$(bash_p "$C")")"
done
ci_blocks "echo 'npm ci' | bash" "echo 'npm ci' ; make" "$(printf "echo 'npm ci'\nmake")"
# A word that is only the NAME of a shell or of eval, given as an argument, runs nothing.
for C in "gh issue create --title bash --body '$INSTALL lodash is refused'" "gh issue create --title sh --body 'cd web && npm ci'" \
  "gh issue create --title eval --body '$INSTALL lodash'" "gh issue create --label ssh --body '$ADD lodash'" \
  "git commit -m '$INSTALL lodash' --author zsh" "gh issue create --title 'xargs and source' --body '$INSTALL lodash'" \
  "$(printf "cat > /tmp/note.md <<'EOF'\n\$(%s lodash)\n\$(cd web && npm ci)\nEOF" "$INSTALL")" \
  "$(printf 'cat > /tmp/note.md <<"EOF"\n$(%s lodash)\nEOF' "$INSTALL")" \
  "$(printf "cat >> /tmp/note.md <<'EOF'\nthe guard refused \`%s lodash\` and \`npm ci\`\nEOF" "$INSTALL")" \
  "$(printf "cat <<-'EOF'\n\t\`npm ci\`\n\tEOF\ngit status")"; do
  check "a message that names an install passes: $C" 0 "$(run "$(bash_p "$C" "$WTX")")"
done
# Every way round the first design that review found, and its neighbours: a
# shell reached through another command or given joined flags, and a
# here-document whose end word is not quoted, a word or a number.
for C in "env A=1 sh -c '$INSTALL lodash'" "timeout 5 bash -c '$INSTALL lodash'" "find . -name x -exec sh -c '$INSTALL lodash' \\;" \
  "bash --norc -c '$INSTALL lodash'" "bash -lc '$INSTALL lodash'" "bash -ce '$INSTALL lodash'" "sh -ec '$INSTALL lodash'" "bash -xce '$INSTALL lodash'" \
  "$(printf 'cat <<123\n$(%s lodash)\n123' "$INSTALL")" "$(printf 'cat <<-9\n\t$(%s lodash)\n\t9' "$INSTALL")" "$(printf 'cat <<E-1\n$(%s lodash)\nE-1' "$INSTALL")" \
  "$(printf 'gh issue create --body-file - <<EOF\n$(%s lodash)\nEOF' "$INSTALL")" "command eval \"$INSTALL lodash\"" "true && eval '$INSTALL lodash'" \
  "A=1 eval '$INSTALL lodash'" ". <(echo '$INSTALL lodash')" "echo '$INSTALL lodash' | sudo bash" \
  "$(printf 'cat <<EOF\n$(%s lodash)\nEOF' "$INSTALL")" "$(printf 'cat <<-EOF\n\t$(%s lodash)\n\tEOF' "$INSTALL")" \
  "$(printf 'cat << EOF > /tmp/x\nnote $(%s lodash)\nEOF' "$INSTALL")" "$(printf 'cat <<EOF\n`%s lodash`\nEOF' "$INSTALL")" \
  "$(printf "cat <<'EOF'\nnote\nEOF\necho \`%s lodash\`" "$INSTALL")"; do
  check "a real install still blocks: $C" 2 "$(run "$(bash_p "$C")")"
done
# Text that only looks like a note's start, in a comment or a quoted string, hides no line after it.
for C in "$(printf "# see cat <<'EOF' for the shape\necho \`%s lodash\`" "$INSTALL")" "$(printf "echo \"cat <<'EOF'\"\necho \`%s lodash\`" "$INSTALL")" \
  "$(printf "echo 'cat <<\"EOF\"'\necho \`%s lodash\`" "$INSTALL")" "$(printf "git commit -m \"cat <<'EOF'\"\necho \"\`%s lodash\`\"" "$INSTALL")" \
  "$(printf "echo hi # cat <<'EOF'\necho \`%s lodash\`\nEOF" "$INSTALL")" "$(printf "echo \$((1<<2))\necho \`%s lodash\`\n2" "$INSTALL")" \
  "$(printf "# cat <<'EOF'\ncat <<'EOF'\nnote\nEOF\necho \`%s lodash\`" "$INSTALL")" \
  "$(printf "echo \"\$((1<<2))\"\n%s lodash\n2" "$INSTALL")" "$(printf "X=\"a \$((1<<2)) b\"\n%s lodash" "$INSTALL")"; do
  check "an install after text that looks like a note's start still blocks: $C" 2 "$(run "$(bash_p "$C")")"
done
for C in "$(printf "# cat <<'EOF'\ncat > /tmp/note.md <<'EOF'\nthe guard refused \`%s lodash\`\nEOF" "$INSTALL")" \
  "$(printf "echo \"cat <<'EOF'\"\ngit commit -m '%s lodash is refused'" "$INSTALL")"; do
  check "a message after text that looks like a note's start still passes: $C" 0 "$(run "$(bash_p "$C" "$WTX")")"
done
# A note's end word ends the note: a command on a later line is a command.
for C in "$(printf "cat <<'EOF'\nnote\nEOF\n%s lodash" "$INSTALL")" "$(printf "cat > /tmp/n <<'EOF'\nnote\nEOF\n%s lodash" "$INSTALL")" \
  "$(printf "gh issue create --body-file - <<'EOF'\nnote\nEOF\n%s lodash" "$INSTALL")" "$(printf 'cat <<"EOF"\nnote\nEOF\n%s lodash' "$INSTALL")" \
  "$(printf 'cat <<\\EOF\nnote\nEOF\n%s lodash' "$INSTALL")" "$(printf "cat <<-'EOF'\n\tnote\n\tEOF\n%s lodash" "$INSTALL")" \
  "$(printf "cat <<'EOF'\nnote\nEOF\ncat <<'EOF'\nnote\nEOF\n%s lodash" "$INSTALL")" \
  "$(printf "echo hi; cat <<'EOF'\nnote\nEOF\necho done && %s lodash" "$INSTALL")"; do
  check "an install after a note still blocks: $C" 2 "$(run "$(bash_p "$C")")"
done
# An end word that is not plain never reaches this guard: bash-guardrails.sh
# refuses the command, so this guard reads no odd end word. Every form review
# found that hid an install after the note:
for E in "<<'END NOTE'" "<<E'OF'" "<<'E'OF" '<<"E""OF"' "<<E\\OF" "<<'END'\\ NOTE" '<<"E\"OF"'; do
  check "an install after a note with the end word $E is refused" 2 \
    "$(HOOK=${HOOK%/*}/bash-guardrails.sh hook >/dev/null 2>&1 <<<"$(bash_p "$(printf 'cat %s\nnote\nEOF\n%s lodash' "$E" "$INSTALL")")"; echo $?)"
done
ci_blocks "$(printf "cat <<'EOF'\nnote\nEOF\ncd web && npm ci")" "$(printf "cat <<'EOF'\nnote\nEOF\nnpm ci")" \
  "$(printf "gh issue create --body-file - <<'EOF'\nnote\nEOF\nnpm ci")"
ci_blocks "$(printf 'cat <<EOF\n$(cd web && npm ci)\nEOF')" "$(printf 'cat <<EOF\n$(npm ci)\nEOF')" "env A=1 sh -c 'npm ci'" \
  "bash -ce 'cd web && npm ci'" "sh -ec 'npm ci'" "$(printf 'cat <<123\n$(cd web && npm ci)\n123')" "$(printf 'cat <<123\n$(npm ci)\n123')"
# A quoted folder with a space, inside a string a shell runs: read whole or refused, never cut at the space.
mkdir -p "$TMP/work tree/web" "$TMP/work"; ln -s "$TMP/shared/web-modules" "$TMP/work tree/web/node_modules"
for C in "bash -c 'npm --prefix \"$TMP/work tree/web\" ci'" "bash -c \"npm --prefix '$TMP/work tree/web' ci\"" \
  "bash -c 'cd \"$TMP/work tree/web\" && npm ci'" "bash -c \"cd \\\"$TMP/work tree/web\\\" && npm ci\"" "sh -c 'npm --prefix=\"$TMP/work tree/web\" ci'" \
  "bash -c 'npm -C \"$TMP/work tree/web\" ci'" "bash -c \"npm -C '$TMP/work tree/web' ci\"" "bash -c 'pushd \"$TMP/work tree/web\" && npm ci'" "bash -ce 'npm -C \"$TMP/work tree/web\" ci'"; do
  check "npm ci in a quoted folder with a space, run by a shell, blocks: $C" 2 "$(run "$(bash_p "$C" "$TMP")")"
done
# Without its quoted-span reader the guard reads every line whole: installs still block, and so does a message that names one.
mkdir -p "$TMP/nolib"; cp "$HOOK" "$TMP/nolib/"
check "with its quoted-span reader missing the guard refuses a plain install" 2 "$(HOOK=$TMP/nolib/dependency-addition-guard.sh hook >/dev/null 2>&1 <<<"$(bash_p "$INSTALL lodash")"; echo $?)"
check "and refuses npm ci at a linked root" 2 "$(HOOK=$TMP/nolib/dependency-addition-guard.sh hook >/dev/null 2>&1 <<<"$(bash_p "npm ci" "$WTX")"; echo $?)"
check "and blocks a message that names an install, never passes one unread" 2 "$(HOOK=$TMP/nolib/dependency-addition-guard.sh hook >/dev/null 2>&1 <<<"$(bash_p "gh issue create --body 'bash -c \"$INSTALL lodash\"'")"; echo $?)"
# Each sender of the hook's list only carries text (gh, rg and decision.sh are run above): a message naming npm ci
# passes, and the same with a real npm ci chained after it blocks. Bugs: a sender left out of the list refuses a
# message that only names the install; a chained install riding through behind a sender.
for C in "git commit -m 'run npm ci in main'" "git tag -a v1 -m 'after npm ci'" "git notes add -m 'ran npm ci'" "echo 'run npm ci'" \
  "printf '%s\n' 'run npm ci'" "cat 'npm ci notes'" "grep -n 'npm ci' docs"; do
  check "a sender's message naming npm ci passes, one with npm ci chained blocks: $C" "0 2" \
    "$(run "$(bash_p "$C" "$WTX")") $(run "$(bash_p "$C; npm ci" "$WTX")")"
done
fi

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
