#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# PreToolUse(Bash) hook: BLOCK a local deploy.sh run whose outgoing RUNTIME-code
# changes lack a recorded CONVERGED adversarial review.
#
# PUSHES ARE ENFORCED IN .githooks/pre-push, not here. A PreToolUse hook can
# only guess at a command string -- it hashed local HEAD against origin/main
# however the push was spelled, so it blocked a quoted command that merely
# NAMED one and said nothing about the refs a push actually ships. pre-push
# receives the real <local sha>/<remote sha> pairs and calls this script's
# --hash-range / --tier-range to reuse ONE definition of the runtime diff.
# deploy.sh has no such hook, so its entry point stays gated here.
#
# Protocol this enforces (the owner's directive, reviewer set narrowed
# since): every phase/sprint that ships runtime code must pass adversarial
# review run to CONVERGENCE before it deploys — a contained-Codex reviewer
# (read-only, findings validated vs source), every confirmed finding fixed,
# repeating until a round surfaces nothing new (CONVERGED: GO). Whether a diff
# needs a marker at all is its CHANGE CLASS (see diff_class): scripts, tools,
# web/e2e and tests carry no marker; every other class needs one. Pushes auto-deploy via Deploy-to-Dev, so the push IS the deploy
# boundary; record-keeping pushes (docs/todo/plans) flow freely.
#
# The marker is .claude/review-convergence.json, written by .githooks/pre-push
# for the diff a push carries. It binds to a sha256 of the outgoing runtime
# diff, so any code change after it invalidates it.
#
# Escape hatch (owner-authorized emergencies only):
#   CONVEYOR_REVIEW_GATE_BYPASS=1 git push ...
#
# --hash-only / --tier-only / --class-only: the current HEAD-vs-base
# runtime-diff hash, tier or change class.
# --hash-range <base> <tip> / --tier-range <base> <tip> / --class-range: the
# same answers for an arbitrary range. --contract-range checks that persisted
# writers and their changed readers are named together by a changed test.
# --converged-ok <reviewers> <class>: exit 0 iff that reviewer set may attest a
# diff of that class. The deploy gate and pre-push both ask here so the rule
# has one home.
#
# TIER AND CLASS ARE SEPARATE ANSWERS ON SEPARATE MODES. Tier (LOW/FULL) is the
# older question -- how many review rounds -- and its callers capture one word,
# so class never joins that output; it gets its own mode and its own
# `class=<name>` line in the block message below.
# Retire when: deploy.sh cannot run from an agent shell and pre-push is the sole caller

# Everything is runtime unless excluded: docs, plans/records, harness config,
# and markdown. New directories are gated by default (exclusion > allowlist).
RUNTIME_PATHSPEC=(-- . ':(exclude)docs' ':(exclude)todo' ':(exclude).claude' ':(exclude)*.md' ':(exclude)**/*.md' ':(exclude).gitignore')
# .claude/hooks is EXECUTABLE POLICY, not the orchestration prose the exclusion
# above is for: the push gate, the commit guards and this script all live there.
# It is carried as a second pathspec because a git exclusion cannot be undone
# for a subdirectory, and hashed alongside the runtime diff so a hook rewritten
# after the review invalidates the marker like any other code change. Tiering
# and class do NOT read it here -- GATE_CI_PATHSPEC already answers for those.
HOOK_PATHSPEC=(-- .claude/hooks)

# LOW tier (the owner's ruling, widened since): a runtime diff confined
# ENTIRELY to presentational CSS (web/src), test files, and/or dev tooling
# (scripts/, tools/, .githooks/ -- never shipped, already exempt from
# needs ONE Codex review round (findings fixed), not the
# full convergence loop. Anything else is FULL tier. Presentational .tsx
# changes are NOT mechanically classifiable (copy changes hide there) -- they
# stay FULL tier. Guard-class tests (conformance / guard / parity / coverage
# -- the CI drift guards the SSOT architecture rests on) are excluded from
# LOW: weakening a drift guard deserves the full loop. package.json is NOT
# tooling: it ships the runtime dependency set.
LOW_TIER_PATTERN='^web/src/.*\.css$|(^|/)__tests__/|\.test\.tsx?$|\.spec\.tsx?$|^scripts/|^tools/|^\.githooks/'
# Derived from the test:guards selector in package.json, which takes ALL of
# shared/**/__tests__/ and src/config/__tests__/ unconditionally plus the
# name filter elsewhere -- a name filter alone exempted most drift guards.
GUARD_CLASS_PATTERN='^shared/.*__tests__/|^src/config/__tests__/|conformance|guard|parity|coverage'

# RISKY paths: the one list. A diff touching any of these gets the most
# expensive review the loop has, so the list is deliberately blunt -- money,
# auth and tenant isolation, and the verification pipeline. Concurrency is the
# fourth entry and is not a path at all: any file that runs a DynamoDB
# transaction is risky wherever it lives (see transact_files).
RISKY_PATHSPEC=(--
  'src/services/billing*' 'src/services/credit*' 'src/services/stripe*'
  'src/middleware/api-rate-limit.ts'
  'src/repositories/usage-repository.ts' 'src/repositories/counter-repository.ts'
  'src/middleware/tenant*' 'src/routes/auth/**' 'src/utils/group-access.ts'
  'src/services/tenant-purge/**'
  'src/services/verification/**' 'src/routes/public-guest/**' 'shared/verification-*'
)

# GATE/CI paths: executable policy. A wrong gate blocks every ship or lets a
# runtime diff through, so this class keeps one reviewer even though tooling
# lost its own. .claude/hooks is here although RUNTIME_PATHSPEC excludes
# .claude entirely -- the class is about what the files DO, not about whether
# the marker mechanism can see them.
# A hook's own TEST does not run in any gate, so it is not executable policy:
# it is a test like every other test, and tooling is its class.
# Four lines added to a hook self-test used to demand a Codex round
# and a worktree main is not allowed to open. The hooks themselves stay in, so a
# guard rewritten after its review still invalidates the marker.
GATE_CI_PATHSPEC=(-- .githooks .claude/hooks ':(exclude).claude/hooks/__tests__/**' .github/workflows)
REPOSITORY_SOURCE_PATHSPEC=(-- src/repositories
  ':(exclude)src/repositories/**/__tests__/**'
  ':(exclude)src/repositories/**/*.test.*'
  ':(exclude)src/repositories/**/*.spec.*')

# TOOLING paths: scripts, tools and tests.
# These have no runtime hash to attest, so a
# tooling-only diff carries no convergence marker and none is demanded of it.
# CSS is deliberately absent: it is shipped product, so it stays a code class.
# A guard-class test is also absent, via the same carve-out the LOW tier makes
# -- weakening a drift guard deserves a reviewer.
# web/e2e is here because it never ships: it is outside web/src and the app
# bundle, and runs only from a developer shell against dev.
TOOLING_PATTERN='^scripts/|^tools/|^web/e2e/|(^|/)__tests__/|\.test\.tsx?$|\.spec\.tsx?$'
MARKER="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null)}/.claude/review-convergence.json"

# The reviewed watermark. The base used to be
# origin/main always, so one new commit re-opened the whole unpushed range and a
# one-line fix inherited the change class of every reviewed unit behind it: on
# 2026-09-13 a one-line `cause:` fix measured risky/FULL against 285 commits.
# The base is the newest commit B such that EVERY commit in origin/main..B is
# covered, walked oldest first: a commit is covered when it lies in a
# Fast lane landing's range (fast-lane.sh land writes main's reflog line
# `fast-lane: land <sha> on <old>` only after its reviewer's GO on old..sha), when
# it is a reviewed Conveyor landing (conveyor_reviewed below), or
# when its own diff is class docs or tooling, which no marker attests anyway.
# Only what is AHEAD of B is hashed. The first uncovered commit stops the walk,
# so a later reviewed landing never hides an unreviewed commit beneath it.
# A rogue reflog line could move this forward, but writing one and
# writing the marker take the same access, so this opens no door the marker did not.
# Falls back to origin/main when the oldest commit is uncovered.

# conveyor_reviewed -- one `<commit> <card>` line per commit Conveyor landed after its review, read from
# the main checkout's card records (cards.jsonl in the folder that this hook's own install's conveyor.sh state-dir
# names for that checkout -- a project on the plugin has no engine of its own -- where conveyor.sh's
# land writes one `landed` line per commit). Reviewed: the card landed on a GO, or under the 3-review rule with every leftover finding
# filed (leftover true, and followups names the issues: conveyor.sh lands nothing when a filing fails). A landed
# line with leftovers and no filed issue, a line that is not a whole record, and a commit with no card record
# give no line, so that commit stays unreviewed. No conveyor.sh beside this hook's install, no state folder from it, or no
# records file (a machine Conveyor does not run on): no line.
# pre-push's parts_note reads this through --conveyor-reviewed, so the two cannot disagree.
conveyor_reviewed() {
  local f e
  e=$(cd "${BASH_SOURCE[0]%/*}/../../conveyor" 2>/dev/null && pwd)/conveyor.sh; [ -f "$e" ] || return 0
  f=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || return 0
  f=$(CONVEYOR_MAIN=${f%/.git} bash "$e" state-dir 2>/dev/null)/cards.jsonl || return 0
  [ -r "$f" ] || return 0
  jq -rR 'fromjson? | objects
    | select(.step == "landed" and .result == "ok")
    | select((.sha | type) == "string" and (.sha | test("^[0-9a-f]{40}$")))
    | select((.card | type) == "string" and (.card | test("^[A-Za-z0-9._-]+$")))
    | select(.leftover == null or ((.leftover == true) and (.followups | type) == "array" and (.followups | length) > 0))
    | "\(.sha) \(.card)"' "$f" 2>/dev/null || true
}

reviewed_base() {
  local tip=${1:-HEAD} fallback=${REVIEW_GATE_BASE_REF:-origin/main} base sha old ahead onpath covered=$'\n'
  git rev-parse --verify -q "$fallback" >/dev/null 2>&1 || { echo "$fallback"; return; }
  ahead=$(git rev-list --reverse --topo-order "$fallback..$tip" 2>/dev/null)
  [ -n "$ahead" ] || { echo "$fallback"; return; }
  ahead=$'\n'$ahead$'\n'
  while read -r sha old; do
    [[ $ahead == *$'\n'"$sha"$'\n'* ]] && covered+=$(git rev-list "$old..$sha" 2>/dev/null)$'\n'
  done < <(git log -g --format=%gs refs/heads/main 2>/dev/null \
    | sed -nE 's/^fast-lane: land ([0-9a-f]{40}) on ([0-9a-f]{40})$/\1 \2/p')
  # A Conveyor landing is one commit, so it covers itself and nothing under it.
  while read -r sha old; do
    [[ $ahead == *$'\n'"$sha"$'\n'* ]] && covered+=$sha$'\n'
  done < <(conveyor_reviewed)
  # The base itself must descend from origin/main: a side commit as base would
  # diff the tip against a tree that lacks origin/main's files, hiding a merge
  # that deletes them.
  onpath=$'\n'$(git rev-list --ancestry-path "$fallback..$tip" 2>/dev/null)$'\n'
  base=$fallback
  for sha in $ahead; do
    if [[ $covered != *$'\n'"$sha"$'\n'* ]]; then
      case $(BASE_REF=$sha^ TIP_REF=$sha diff_class gate) in docs|tooling) ;; *) break ;; esac
    fi
    [[ $onpath == *$'\n'"$sha"$'\n'* ]] && base=$sha
  done
  echo "$base"
}

runtime_hash() {
  # mode 'record': prefer the staged index when it differs from HEAD
  # (record-after-staging workflow). mode 'gate': ALWAYS hash the committed
  # range — that is what a push actually ships; staged-but-uncommitted edits
  # must not shift the gate's view of the outgoing diff. Both directions are
  # base->newer, so staged content produces the same patch text once
  # committed. Volatile 'index ' lines are stripped. The hook diff is appended
  # to the runtime one so a single sha256 covers both; the order is fixed, so
  # the same tree always hashes the same.
  # --no-renames: a rename shows only its destination in name-lists, so a
  # production file renamed into a test path would classify LOW; forcing
  # add+delete keeps both sides visible to tiering AND hashing.
  # --binary: without it a binary change carries no content in the patch once
  # 'index' lines are stripped, so successive binary changes hashed identically.
  local mode="$1" diff_text
  if ! git rev-parse --verify -q "$BASE_REF" >/dev/null 2>&1; then
    echo "NO_BASE"
    return
  fi
  if [ "$mode" = "record" ] && ! git diff --cached --quiet 2>/dev/null; then
    diff_text=$(git diff --cached --no-renames --binary "$BASE_REF" "${RUNTIME_PATHSPEC[@]}" 2>/dev/null
                git diff --cached --no-renames --binary "$BASE_REF" "${HOOK_PATHSPEC[@]}" 2>/dev/null)
  else
    diff_text=$(git diff --no-renames --binary "$BASE_REF" "${TIP_REF:-HEAD}" "${RUNTIME_PATHSPEC[@]}" 2>/dev/null
                git diff --no-renames --binary "$BASE_REF" "${TIP_REF:-HEAD}" "${HOOK_PATHSPEC[@]}" 2>/dev/null)
  fi
  if [ -z "$diff_text" ]; then
    echo "EMPTY"
    return
  fi
  echo "$diff_text" | grep -v '^index ' | sha256sum | awk '{print $1}'
}

changed_files() {
  # Changed files under the given pathspec, same staged-vs-committed semantics
  # as runtime_hash. --no-renames so BOTH sides of a rename are listed (see
  # runtime_hash). Every "which files did this diff touch" question goes
  # through here, so the three pathspecs cannot answer on different diffs.
  local mode="$1"; shift
  if ! git rev-parse --verify -q "$BASE_REF" >/dev/null 2>&1; then
    return
  fi
  if [ "$mode" = "record" ] && ! git diff --cached --quiet 2>/dev/null; then
    git diff --cached --no-renames "$BASE_REF" --name-only "$@" 2>/dev/null
  else
    git diff --no-renames "$BASE_REF" "${TIP_REF:-HEAD}" --name-only "$@" 2>/dev/null
  fi
}

runtime_files() { changed_files "$1" "${RUNTIME_PATHSPEC[@]}"; }

diff_tier() {
  # LOW iff every changed runtime file matches LOW_TIER_PATTERN and no TEST
  # file is guard-class (drift guards get the full loop). The guard-class
  # check skips .css files -- a stylesheet named coverage.css is
  # presentational, not a drift guard.
  local mode="$1" files
  files=$(runtime_files "$mode")
  if [ -z "$files" ]; then
    echo "EMPTY"
  elif echo "$files" | grep -qvE "$LOW_TIER_PATTERN"; then
    echo "FULL"
  elif echo "$files" | grep -v '\.css$' | grep -qiE "$GUARD_CLASS_PATTERN"; then
    echo "FULL"
  else
    echo "LOW"
  fi
}

risky_files()  { changed_files "$1" "${RISKY_PATHSPEC[@]}"; }
gate_ci_files() { changed_files "$1" "${GATE_CI_PATHSPEC[@]}"; }

transact_files() {
  # Changed files whose CONTENT runs a DynamoDB transaction on EITHER SIDE of
  # the range. The whole file decides, not the hunk: a transaction's invariants
  # are a property of the code around it, so an edit anywhere in the file can
  # break them.
  #
  # The BASE side counts because the tip alone cannot see the change this class
  # most needs to catch: a diff that DELETES or replaces a file's last
  # transaction call -- moving it off an atomic write -- leaves no match at the
  # tip at all. Either side matching makes the file risky. Only the emptiness
  # of the output is read, so the two greps' `<rev>:` prefixes are left as git
  # prints them.
  local mode="$1" files
  files=$(runtime_files "$mode")
  [ -n "$files" ] || return
  {
    if [ "$mode" = "record" ] && ! git diff --cached --quiet 2>/dev/null; then
      printf '%s\n' "$files" | xargs -r -d '\n' -- git grep -l --cached -E 'transactWrite|TransactWrite' -- 2>/dev/null
    else
      printf '%s\n' "$files" | xargs -r -d '\n' -- git grep -l -E 'transactWrite|TransactWrite' "${TIP_REF:-HEAD}" -- 2>/dev/null
    fi
    printf '%s\n' "$files" | xargs -r -d '\n' -- git grep -l -E 'transactWrite|TransactWrite' "$BASE_REF" -- 2>/dev/null
  } | sort -u
}

diff_class() {
  # docs -> risky -> gate-ci -> tooling -> runtime -> cross-file, first match
  # wins. docs needs BOTH file sets empty: .claude/hooks is invisible to
  # RUNTIME_PATHSPEC, so a hook-only diff would otherwise read as prose.
  # cross-file is "more than one runtime file", counting only the files that
  # SHIP: tooling and test files are excluded from the count, so one source
  # file plus its tests and runners is still a single-reviewer runtime diff.
  # A contract spanning shipped files is where the drift findings live, and
  # file count is the part of that a shell hook can decide. A guard-class diff
  # of tooling files alone counts zero and lands on runtime -- the tooling
  # branch above already refused it, and it must stay a reviewed class.
  local mode="$1" files shipped
  files=$(runtime_files "$mode")
  shipped=$(printf '%s\n' "$files" | grep -vcE "$TOOLING_PATTERN")
  if [ -z "$files" ] && [ -z "$(gate_ci_files "$mode")" ]; then
    # .claude/ is docs for its prose only; its loop scripts are tooling code.
    if [ -n "$(changed_files "$mode" -- .claude/scripts ':(exclude)*.md')" ]; then echo tooling; else echo docs; fi
  elif [ -n "$(risky_files "$mode")" ] || [ -n "$(transact_files "$mode")" ]; then
    echo risky
  elif [ -n "$(gate_ci_files "$mode")" ]; then
    echo gate-ci
  elif [ -n "$files" ] \
    && ! printf '%s\n' "$files" | grep -qvE "$TOOLING_PATTERN" \
    && ! printf '%s\n' "$files" | grep -qiE "$GUARD_CLASS_PATTERN"; then
    echo tooling
  elif [ "$shipped" -le 1 ]; then
    echo runtime
  else
    echo cross-file
  fi
}

converged_ok() {
  # May this reviewer set attest a CONVERGED-GO on this class? Codex reviews
  # every attestable diff, so its token is required, and it is the only one:
  # cross-file and risky used to demand a second family, but that family was
  # Claude reading Claude-written code, and it agreed with the writer (an
  # in-pane Codex review approved a tree the outside Codex seat then failed
  # five times). Docs is not attestable at all. The clean Codex
  # self-review review-round.sh runs at round 1 (codex-self-review) attests
  # runtime and tooling only (the owner's ruling).
  # This is asked by CONSUMERS (the deploy gate, pre-push) about a marker that
  # may have been hand-edited, so it re-derives the whole rule rather than
  # trusting that the recorder wrote the file.
  # EXACT tokens, never substrings -- 'no-codex' is not the codex token.
  local toks
  toks=$(echo "$1" | tr ',' '\n' | sed 's/[[:space:]]//g')
  if echo "$toks" | grep -qxi codex; then
    case "$2" in gate-ci|runtime|cross-file|risky) return 0 ;; esac
  fi
  if echo "$toks" | grep -qxi codex-self-review; then
    case "$2" in runtime|tooling) return 0 ;; esac
  fi
  return 1
}

file_at_tip() { # <mode> <path>: the staged or committed tip-side contents
  if [ "$1" = record ] && ! git diff --cached --quiet 2>/dev/null; then
    git show ":$2" 2>/dev/null || true
  else
    git show "${TIP_REF:-HEAD}:$2" 2>/dev/null || true
  fi
}

names_for() { # <mode> <path>: mechanical names a changed test may cite
  local mode=$1 path=$2 stem
  basename "$path"
  stem=$(basename "$path"); stem=${stem%.*}; printf '%s\n' "$stem"
  exported_names_for "$mode" "$path"
}

exported_names_for() { # <mode> <path>
  file_at_tip "$1" "$2" | sed -nE \
    's/^[[:space:]]*export[[:space:]]+(async[[:space:]]+)?(class|function|interface|type|const|let|var|enum)[[:space:]]+([A-Za-z_][A-Za-z0-9_]*).*/\3/p'
}

test_names() { # <mode> <test> <source>
  local mode=$1 test=$2 source=$3 contents token
  contents=$(file_at_tip "$mode" "$test")
  while IFS= read -r token; do
    [ -n "$token" ] && printf '%s\n' "$contents" | grep -Fq "$token" && return 0
  done < <(names_for "$mode" "$source")
  return 1
}

# The writer file's own reader stands in for a separate reader file only when
# the test names a reader-shaped export AND a writer-shaped one. Any other
# export stands for neither side: `writeWidget` or `readWidget` beside an
# unrelated `VERSION` exercises only one half of the round trip.
test_names_writer_and_reader() { # <mode> <test> <source>
  local mode=$1 test=$2 source=$3 contents token readers=0 writers=0
  contents=$(file_at_tip "$mode" "$test")
  while IFS= read -r token; do
    [ -n "$token" ] && printf '%s\n' "$contents" | grep -Fq "$token" || continue
    if [[ "$token" =~ ^(get|read|find|load|list|query|parse|map|fetch|scan|decode)[A-Z_] ]]; then
      readers=$((readers+1))
    elif [[ "$token" =~ ^(write|save|create|put|update|delete|upsert|insert|store|increment|append|persist|record|set|add|remove|batch|transact)[A-Z_] ]]; then
      writers=$((writers+1))
    fi
  done < <(exported_names_for "$mode" "$source" | sort -u)
  [ "$readers" -ge 1 ] && [ "$writers" -ge 1 ]
}

shared_contract_file() { # <mode> <path>
  local mode=$1 path=$2 text token repo_text
  text=$(file_at_tip "$mode" "$path")
  printf '%s\n' "$text" | grep -qE 'export[[:space:]]+(interface|type)|[Ss]chema' || return 1
  if [ "$mode" = record ] && ! git diff --cached --quiet 2>/dev/null; then
    repo_text=$(git grep -h '' "${REPOSITORY_SOURCE_PATHSPEC[@]}" 2>/dev/null || true)
  else
    repo_text=$(git grep -h '' "${TIP_REF:-HEAD}" "${REPOSITORY_SOURCE_PATHSPEC[@]}" 2>/dev/null || true)
  fi
  while IFS= read -r token; do
    [ -n "$token" ] && printf '%s\n' "$repo_text" | grep -Fq "$token" && return 0
  done < <(names_for "$mode" "$path")
  return 1
}

changed_hunks() { # <mode> <path>: the -U0 diff of one file, staged or committed; --text so a `-diff` attribute hides no hunk
  if [ "$1" = record ] && ! git diff --cached --quiet 2>/dev/null; then
    git diff --cached --text -U0 "$BASE_REF" -- "$2" 2>/dev/null
  else
    git diff --text -U0 "$BASE_REF" "${TIP_REF:-HEAD}" -- "$2" 2>/dev/null
  fi
}

infra_contract_file() { # <mode> <path>
  changed_hunks "$1" "$2" \
    | grep -qE '^[+-][^+-].*(partitionKey|sortKey|attributeName|AttributeDefinitions|KeySchema)'
}

# A writer is a repository file whose changed CODE lines sit in a symbol (the
# function, method or class preamble around them) that carries a write token.
# The whole file is the wrong unit: a read-only edit in a module that also
# writes asked for a producer-reader test. A blank or comment-only line
# changes no persisted shape either (prism-unit-5, 2026-09-10, a one-word doc
# comment edit cost a ship). Removed lines are placed in the base file's
# symbols, added lines in the tip's.
# ponytail: symbols are declaration-shaped lines nested by indentation, so
# misindented code can misplace a line. Upgrade to a TS parser if that bites.
repository_write_file() { # <mode> <path>
  local mode=$1 path=$2
  awk -v W='(Put(Command|Item)|Update(Command|Item)|Delete(Command|Item)|TransactWrite|BatchWrite|write[A-Z_]|save[A-Z_]|create[A-Z_]|async[[:space:]]+(put|update|delete|save|create)[A-Z_])' '
    FILENAME == ARGV[1] {
      if ($0 ~ /^@@/) { split($2, o, ","); split($3, n, ","); ol = -o[1]; nl = substr(n[1], 2) + 0; hunk = 1; next }
      if (!hunk) next
      code = $0 !~ /^[+-][[:space:]]*(\/\/|\/\*|\*|$)/
      if ($0 ~ /^-/) { if (code) want["b", ol] = 1; ol++ }
      else if ($0 ~ /^\+/) { if (code) want["t", nl] = 1; nl++ }
      next
    }
    {
      f = FILENAME == ARGV[2] ? "b" : "t"
      match($0, /^[[:space:]]*/); ind = RLENGTH; blank = $0 ~ /^[[:space:]]*$/; closes = 0
      # Declarations nest by indentation: a deeper line stays inside the open
      # one, a `)` at its indent continues its signature, a `}` closes it.
      while (!blank && d[f] > 0 && (ind < si[f, d[f]] || (ind == si[f, d[f]] && $0 !~ /^[[:space:]]*[})]/))) d[f]--
      if (!blank && d[f] > 0 && ind == si[f, d[f]] && $0 ~ /^[[:space:]]*}/) closes = 1
      isclass = $0 ~ /^[[:space:]]*(export[[:space:]]+)?(default[[:space:]]+)?(abstract[[:space:]]+)?class[[:space:]]/
      if (!closes && !blank &&
          $0 !~ /^[[:space:]]*(if|for|while|switch|catch|return|await|throw|new|else|do|typeof|super)([^A-Za-z0-9_$]|$)/ &&
          $0 !~ /[;,][[:space:]]*$/ &&
          (isclass ||
           $0 ~ /^[[:space:]]*(export[[:space:]]+)?(default[[:space:]]+)?((public|private|protected|static|async|readonly|override|get|set)[[:space:]]+)*(function[[:space:]]*\*?[[:space:]]*)?[A-Za-z_$][A-Za-z0-9_$]*[[:space:]]*(<[^>]*>)?[[:space:]]*\(/ ||
           $0 ~ /^[[:space:]]*(export[[:space:]]+)?(const|let)[[:space:]]+[A-Za-z_$][A-Za-z0-9_$]*[[:space:]]*(:[^=]*)?=[[:space:]]*(async[[:space:]]*)?(\(|[A-Za-z_$][A-Za-z0-9_$]*[[:space:]]*=>)/)) {
        d[f]++; si[f, d[f]] = ind; sc[f, d[f]] = isclass; sid[f, d[f]] = ++nsym[f]
        if (!isclass) {
          nm = $0
          sub(/^[[:space:]]*(export[[:space:]]+)?(default[[:space:]]+)?((public|private|protected|static|async|readonly|override|get|set|const|let)[[:space:]]+)*(function[[:space:]]*\*?[[:space:]]*)?/, "", nm)
          match(nm, /^[A-Za-z_][A-Za-z0-9_]*/); name[f, nsym[f]] = substr(nm, 1, RLENGTH)
        }
      }
      # A line belongs to its OUTERMOST enclosing function, so a nested helper
      # never splits a write method; else its innermost class; else the preamble.
      s = 0
      for (k = 1; k <= d[f] && !s; k++) if (!sc[f, k]) s = sid[f, k]
      if (!s && d[f]) s = sid[f, d[f]]
      at[f, FNR] = s
      body[f, s] = body[f, s] "\n" $0
      if (closes) d[f]--
    }
    END {
      # A symbol writes when its own text has a write token, or when a writing
      # symbol in the same file names it: a helper building a stored item
      # changes the persisted shape as surely as the Put beside it does.
      split("b t", sides, " ")
      for (x in sides) {
        f = sides[x]
        for (i = 0; i <= nsym[f]; i++) w[f, i] = body[f, i] ~ W
        do {
          grew = 0
          for (i = 1; i <= nsym[f]; i++) {
            if (w[f, i] || name[f, i] == "") continue
            re = "(^|[^A-Za-z0-9_$])" name[f, i] "([^A-Za-z0-9_$]|$)"
            for (j = 0; j <= nsym[f]; j++) if (j != i && w[f, j] && body[f, j] ~ re) { w[f, i] = grew = 1; break }
          }
        } while (grew)
      }
      for (k in want) { split(k, p, SUBSEP); if (w[p[1], at[p[1], p[2]]]) exit 0 }
      exit 1
    }
  ' <(changed_hunks "$mode" "$path") \
    <(git show "$BASE_REF:$path" 2>/dev/null || true) \
    <(file_at_tip "$mode" "$path")
}

persisted_contract_ok() { # <mode>
  local mode=$1 files tests sources writers path test source covered
  files=$(changed_files "$mode" -- .)
  [ -n "$files" ] || return 0
  tests=$(printf '%s\n' "$files" | grep -E '(^|/)__tests__/|\.(test|spec)\.(ts|tsx|js|sh)$' || true)
  sources=$(printf '%s\n' "$files" | grep -Ev '(^|/)__tests__/|\.(test|spec)\.(ts|tsx|js|sh)$|\.md$' || true)
  writers=""
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    # A writer DELETED at the tip writes nothing new: there is no shape a
    # reader could be tested against, and no test can name a file that is
    # gone. Only a writer that still exists needs the producer-reader test.
    [ -n "$(file_at_tip "$mode" "$path")" ] || continue
    case "$path" in
      src/repositories/*) repository_write_file "$mode" "$path" && writers="$writers$path"$'\n' ;;
      shared/*) shared_contract_file "$mode" "$path" && writers="$writers$path"$'\n' ;;
      infra/*) infra_contract_file "$mode" "$path" && writers="$writers$path"$'\n' ;;
    esac
  done <<< "$sources"
  [ -n "$writers" ] || return 0

  while IFS= read -r path; do
    [ -n "$path" ] || continue
    covered=0
    while IFS= read -r test; do
      [ -n "$test" ] || continue
      test_names "$mode" "$test" "$path" || continue
      if test_names_writer_and_reader "$mode" "$test" "$path"; then covered=1; break; fi
      while IFS= read -r source; do
        [ -n "$source" ] && [ "$source" != "$path" ] || continue
        if test_names "$mode" "$test" "$source"; then covered=1; break; fi
      done <<< "$sources"
      [ "$covered" = 1 ] && break
    done <<< "$tests"
    if [ "$covered" != 1 ]; then
      echo "BLOCKED: persisted-contract writer $path needs one changed test that names both it and a changed reader." >&2
      return 2
    fi
  done <<< "$writers"
  return 0
}

# A flag is a CLI mode (pre-push, the recorder, the loop) and reads no payload.
[ -n "${1-}" ] || INPUT=$(cat)
. "${BASH_SOURCE[0]%/*}/lib/hook-fire-log.sh" 2>/dev/null && hook_fire_log_arm "${INPUT-}" "${1:+CLI}"

# One definition of the base: pre-push asks for it rather than keeping its own
# copy, so the hook and the recorder cannot drift apart on what is unreviewed.
if [ "$1" = "--base-only" ]; then
  # `--base-only <tip>` answers for that tip (a pushed ref); with none, HEAD's answer as before.
  printf '%s\n' "${REVIEW_GATE_BASE_REF:-$(reviewed_base "${2:-HEAD}")}"
  exit 0
fi
# --conveyor-reviewed: the `<commit> <card>` lines of conveyor_reviewed, for pre-push's parts_note.
if [ "$1" = "--conveyor-reviewed" ]; then
  conveyor_reviewed
  exit 0
fi
# Resolved only where it is read: the walk classifies commits, and every Bash call reaches this hook.
case ${1-} in --hash-only|--tier-only|--class-only|--contract-only) BASE_REF="${REVIEW_GATE_BASE_REF:-$(reviewed_base)}" ;; esac
if [ "$1" = "--hash-only" ]; then
  runtime_hash record
  exit 0
fi
if [ "$1" = "--tier-only" ]; then
  diff_tier record
  exit 0
fi
if [ "$1" = "--hash-range" ]; then
  BASE_REF="$2" TIP_REF="$3" runtime_hash gate
  exit 0
fi
if [ "$1" = "--tier-range" ]; then
  BASE_REF="$2" TIP_REF="$3" diff_tier gate
  exit 0
fi
if [ "$1" = "--class-only" ]; then
  diff_class record
  exit 0
fi
if [ "$1" = "--class-range" ]; then
  BASE_REF="$2" TIP_REF="$3" diff_class gate
  exit 0
fi
if [ "$1" = "--contract-only" ]; then
  persisted_contract_ok record
  exit $?
fi
if [ "$1" = "--contract-range" ]; then
  BASE_REF="$2" TIP_REF="$3" persisted_contract_ok gate
  exit $?
fi
if [ "$1" = "--converged-ok" ]; then
  converged_ok "$2" "$3"
  exit $?
fi

# Fail CLOSED if jq is missing: without it the parse below yields an empty
# command, which would otherwise be read as "not a push" and permitted. Only
# block when the raw payload looks like a deploy, so an absent jq does not
# brick every unrelated Bash call. jq is a documented, guaranteed dependency;
# this is the accidental-breakage safety net, not evasion hardening.
if ! command -v jq >/dev/null 2>&1; then
  if printf '%s' "$INPUT" | grep -qE 'deploy\.sh'; then
    echo "BLOCKED: review gate needs jq to verify what looks like a deploy command, but jq is not installed -- failing closed. Install jq (or use the documented emergency bypass)." >&2
    exit 2
  fi
  exit 0
fi
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
[ -z "$CMD" ] && exit 0
# Normalize backslash-newline continuations so a split `git push` matches
# the same as its single-line form.
CMD=$(printf '%s' "$CMD" | sed -z 's/\\\n/ /g')

# One deploy boundary reaches this hook: the local deploy.sh fallback. Pushes
# are gated in .githooks/pre-push against the refs they actually ship.
#
# THE TOKEN MUST BE IN COMMAND POSITION, not merely present. A grep whose last
# argument is the script, or a commit message quoting its name, is not a deploy,
# and refusing those is the false-block class this hook is being narrowed out
# of. Command position survives a wrapper: `nohup`, `sudo -u x`, `bash -x`, a
# shell's `-c` program and `if ...; then` all RUN the script, and each walked
# past a check that knew only the bare spelling.
case "${CMD//[\'\"\\]/}" in *deploy.sh*) ;; *) exit 0 ;; esac
. "${BASH_SOURCE[0]%/*}/lib/strip-quoted.sh" 2>/dev/null
type strip_quoted >/dev/null 2>&1 || { echo "BLOCKED: review gate could not load .claude/hooks/lib/strip-quoted.sh, so it cannot tell a deploy from a mention of one -- failing closed. Restore it (git checkout .claude/hooks/lib/strip-quoted.sh) and retry." >&2; exit 2; }

# deploy_invoked <command text>: 0 when bash would RUN deploy.sh. Both checks
# below ask this one question. Quoted text, comments and heredoc bodies are
# data (strip-quoted.sh); each remaining command is read word by word past its
# assignments, compound keywords and wrappers, with the options they take.
# ponytail: the wrapper list is kept by hand, and a quoted path holding a space
# reads as data; add a wrapper here when one is seen carrying a deploy.
deploy_invoked() {
  local TEXT=$1 Q=$'\x01' P=$'\x02' SEG W OP VAL REST M
  local -a BODY=()
  local C_OPERAND="[[:space:]]-[[:alnum:]]*c[[:space:]]+('([^']*)'|\"(([^\"\\\\]|\\\\.)*)\")"
  # A quoted -c value would be stripped as data, so each one is swapped for a
  # numbered token first. A token that lands on a shell's -c is that shell's
  # program; on any other command (`grep -c 'x'`) or inside data it is nothing.
  REST=$TEXT TEXT=""
  while [[ $REST =~ $C_OPERAND ]]; do
    M=${BASH_REMATCH[0]}; W=${BASH_REMATCH[2]}${BASH_REMATCH[3]}
    TEXT+=${REST%%"$M"*}${M%%[\'\"]*}$P${#BODY[@]}
    BODY+=("${W//\\\"/\"}")
    REST=${REST#*"$M"}
  done
  TEXT+=$REST
  while IFS= read -r SEG; do
    set -f; set -- $SEG; set +f
    while [ $# -gt 0 ]; do
      W=${1//$Q/}
      case "$W" in [A-Za-z_]*=*) shift; continue ;; esac
      # VAL = this word's options whose value is the NEXT word.
      case "${W##*/}" in
        if|then|else|elif|do|while|until|'!'|'{'|nohup|eval|builtin|source|.) VAL='' ;;
        time) VAL='-o|-f' ;;
        env) VAL='-u|-C|-S|-P' ;;
        exec) VAL='-a' ;;
        sudo) VAL='-u|-g|-h|-p|-C|-D|-R|-T|-U|-r|-t' ;;
        timeout|gtimeout) VAL='-k|-s' ;;
        command) case "${2-}" in -v|-V) break ;; esac; VAL='' ;; # a lookup, not a run
        bash|sh|zsh) VAL='-o|-O|\+o|\+O|--rcfile|--init-file' ;;
        *) break ;;
      esac
      shift
      while [ $# -gt 0 ]; do
        OP=${1//$Q/}
        if [[ $OP =~ ^-[[:alnum:]]*c$ && $OP != *n* && ${W##*/} =~ ^(bash|sh|zsh)$ ]]; then
          # The next word is a PROGRAM: a quoted one by its token, a plain
          # one as the command word the walk reaches next. The words after a
          # quoted program are its $0 and arguments, never a command.
          shift
          if [[ ${1-} =~ ^$P([0-9]+) ]]; then deploy_invoked "${BODY[${BASH_REMATCH[1]}]}" && return 0; continue 3; fi
          break
        elif [[ $OP =~ ^-[[:alpha:]]*n[[:alpha:]]*$ && ${W##*/} =~ ^(bash|sh|zsh)$ ]]; then
          continue 3 # -n reads the script for syntax and runs nothing
        elif [ -n "$VAL" ] && [[ $OP =~ ^($VAL)$ ]]; then shift; [ $# -gt 0 ] && shift
        elif [[ $OP == [-+]* ]]; then shift
        else break
        fi
      done
      case "${W##*/}" in timeout|gtimeout) [ $# -gt 0 ] && shift ;; esac # the duration
    done
    W=${1-}; W=${W//$Q/}
    case "$W" in deploy.sh|*/deploy.sh) return 0 ;; esac
  done < <({ strip_quoted "$TEXT" "$Q"; echo; } | sed 's/[<>]/ & /g' | tr ';&|()`' '\n')
  return 1
}
deploy_invoked "$CMD" || exit 0

# The token must be parsed from the command TEXT: PreToolUse hooks are
# separate processes, so an inline `VAR=1 git push` prefix never reaches the
# hook's own environment (the env check is kept for an exported variable).
# ANCHORED to the documented prefix form: an unanchored match let a compound
# command that merely MENTIONED the token (a commit message documenting this
# hook + `&& git push`) ship unreviewed -- a false PERMIT at the deploy
# boundary, the inverse of the accepted fail-closed over-match class. The
# trailing space also rejects `=10`-style near-values.
if [ "${CONVEYOR_REVIEW_GATE_BYPASS:-0}" = "1" ]; then
  HOOK_FIRE_ADVISE=1; echo "REVIEW GATE BYPASSED via exported CONVEYOR_REVIEW_GATE_BYPASS=1 -- owner-authorized emergencies only. This deploy ships WITHOUT a converged adversarial review." >&2
  exit 0
fi
if echo "$CMD" | grep -qE '^[[:space:]]*CONVEYOR_REVIEW_GATE_BYPASS=1[[:space:]]'; then
  # The prefix token bypasses ONE simple command. With separators present,
  # the bypassed first segment is stripped and the REMAINDER stays gated --
  # `BYPASS=1 git push A && git push B` must not exempt the second push.
  CMDX=$(printf '%s' "$CMD" | tr '\n' ';')
  case "$CMDX" in
    *';'*|*'&'*|*'|'*)
      CMD=$(printf '%s' "$CMDX" | sed -E 's/^[[:space:]]*CONVEYOR_REVIEW_GATE_BYPASS=1[[:space:]][^;&|]*//')
      if ! deploy_invoked "$CMD"; then
        HOOK_FIRE_ADVISE=1; echo "REVIEW GATE BYPASSED via CONVEYOR_REVIEW_GATE_BYPASS=1 prefix -- owner-authorized emergencies only. This deploy ships WITHOUT a converged adversarial review." >&2
        exit 0
      fi
      echo "Review gate: bypass prefix covers only the FIRST command; a further deploy in the same command stays gated." >&2
      ;;
    *)
      HOOK_FIRE_ADVISE=1; echo "REVIEW GATE BYPASSED via CONVEYOR_REVIEW_GATE_BYPASS=1 prefix -- owner-authorized emergencies only. This deploy ships WITHOUT a converged adversarial review." >&2
      exit 0
      ;;
  esac
fi

BASE_REF="${REVIEW_GATE_BASE_REF:-$(reviewed_base)}"
HASH=$(runtime_hash gate)

if [ "$HASH" = "NO_BASE" ]; then
  # Fail CLOSED: an unresolvable base is precisely when the gate cannot tell
  # what is shipping. (Was advisory-allow; if you are offline you cannot push
  # anyway, so requiring a fetch costs nothing real.)
  echo "BLOCKED: review gate cannot resolve $BASE_REF, so it cannot determine the outgoing runtime diff. Run 'git fetch origin' first." >&2
  echo "Try: git fetch origin" >&2
  exit 2
fi

if [ "$HASH" = "EMPTY" ]; then
  # Docs/todo/plans/.claude-only push — no runtime surface, no review required.
  exit 0
fi

# A tooling diff (scripts, tools, web/e2e, tests) has no runtime hash to
# attest, so no marker is demanded of it here. A docs diff (e.g. a hook
# self-test) is unattestable the same way: converged_ok refuses it.
# .githooks/pre-push carries the same skip.
SKIP_CLASS=$(diff_class gate)
case "$SKIP_CLASS" in docs|tooling)
  echo "Adversarial review gate: class=$SKIP_CLASS (docs, or scripts / tools / web-e2e / tests only) -- no runtime surface to attest, no marker required."
  exit 0 ;;
esac

if [ -f "$MARKER" ]; then
  RECORDED_HASH=$(jq -r '.contentHash // empty' "$MARKER" 2>/dev/null)
  VERDICT=$(jq -r '.verdict // empty' "$MARKER" 2>/dev/null)
  ROUNDS=$(jq -r '.rounds // "?"' "$MARKER" 2>/dev/null)
  REVIEWERS_REC=$(jq -r '.reviewers // empty' "$MARKER" 2>/dev/null)
  if [ "$RECORDED_HASH" = "$HASH" ]; then
    # EXACT verdict match: prefix matching accepted CONVERGED-NO-GO and
    # LOW-TIER-<anything>, letting a failed round authorize a deploy.
    if echo "$VERDICT" | grep -qiE '^converged-go$'; then
      # A codex-only CONVERGED-GO attests every attestable class: gate-ci,
      # runtime, cross-file and risky. The class is recomputed here rather than
      # read from the marker: the marker is bound to this exact diff, so the
      # diff itself is the honest answer.
      CLASS=$(diff_class gate)
      if converged_ok "$REVIEWERS_REC" "$CLASS"; then
        echo "Adversarial review gate: CONVERGED review on record for this exact runtime diff ($ROUNDS rounds, $REVIEWERS_REC, class=$CLASS) -- deploy permitted."
        exit 0
      fi
      echo "Adversarial review gate: the recorded reviewers ($REVIEWERS_REC) cannot attest a class=$CLASS diff -- every attestable class needs the exact codex token." >&2
    fi
    # LOW-TIER marker is honored only while the diff still qualifies as LOW --
    # a later edit adding a FULL-tier file re-blocks even with a matching hash
    # (belt over the hash braces; hash would differ anyway).
    if echo "$VERDICT" | grep -qiE '^low-tier-go$' && [ "$(diff_tier gate)" = "LOW" ]; then
      echo "Adversarial review gate: LOW-TIER review on record (single Codex round, CSS/test-only diff) -- deploy permitted."
      exit 0
    fi
    # The pre-push hook's own marker: no combined review ran, its parts were reviewed where they were built. It
    # permits the deploy and shows the parts, unreviewed commits first (show, not block).
    if [ "$VERDICT" = "PARTS-REVIEWED" ]; then
      PARTS=$(jq -r '.parts // empty' "$MARKER" 2>/dev/null)
      UNREVIEWED=$(printf '%s' "$PARTS" | tr ',' '\n' | sed -n 's/^unreviewed://p' | paste -sd' ' -)
      echo "Adversarial review gate: NO combined review ran for this diff; reviewed in parts: ${PARTS:-none} -- deploy permitted."
      echo "Adversarial review gate: unreviewed commits: ${UNREVIEWED:-none}"
      exit 0
    fi
  fi
fi

TIER=$(diff_tier gate)
cat >&2 <<EOF
BLOCKED: this deploy ships runtime-code changes with NO adversarial review on record for the current diff (tier: $TIER).
class=$(diff_class gate)

The marker ($MARKER) is written by .githooks/pre-push for the diff a push carries;
none on record matches this diff.
Current runtime-diff hash: $HASH
(The marker binds to this hash -- any further code edit invalidates it.)
EOF
exit 2
