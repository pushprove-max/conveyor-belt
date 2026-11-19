# SPDX-License-Identifier: Apache-2.0
# The shared setup of the engine cases, sourced once by the runner (../conveyor.test.sh) before the case files
# (tests/*.test.sh): the scratch folder, the environment, the stubs, setup, loop, st, fail and the case runner.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
# The cases' own sed -i and flock are GNU calls: on macOS they run Homebrew's, as the engine's do (portable.sh).
. "$SRC/lib/portable.sh"; p_tools
# wait_until: a case waits for a condition, never a set time (wait.sh).
. "$SRC/tests/wait.sh"
T=$(mktemp -d); trap 'chmod -R u+w "$T"; rm -rf "$T"' EXIT # u+w: the installs are read-only
# Git reaches only the scratch folder's repos (lib/gitfence.sh): under the GIT_DIR `git bisect run` exports, the
# fixture's `git -C "$R" init`, `commit -qm init` and `git init --bare .../origin` (fixture(), below) worked on the
# checkout the run was started in. Each case starts in its own folder, $T/$CASE (case_keep).
. "$SRC/lib/gitfence.sh"; gitfence "$T"
# The machine's test slots (lib/slots.sh), which each case takes one of (the runner; run_case): the pool of the
# runner's own host file (the machine's, or the testSlotsDir it names) and this run's home slot, read before the
# cases' environment below names a host file of their own. A loop a case runs is told the case's slot
# (CONVEYOR_TEST_SLOT, run_case) and this pool (CONVEYOR_TEST_POOL, read where the case's host file names no pool of
# its own), and runs its tests on that slot, taking none: never waiting for one of the machine's slots.
. "$SRC/lib/slots.sh"; slot_pool || exit 1
export CONVEYOR_TEST_POOL=$SLOT_N:$SLOT_DIR
# A run kept to one slot (CONVEYOR_TEST_ONESLOT) keeps this runner's cases on its slot (slot_pool read it): the loops
# the cases run take slots as any other run does.
unset CONVEYOR_TEST_ONESLOT
# A run inside a Conveyor card inherits the loop's own environment. CARDCTL is the loop's control record (run.sh hands
# it to each card): a case's card read the belt's rules for its own (with the belt's "visible changes need the owner's
# yes" off, t_branchvisible's card landed).
# CONVEYOR_MAIN and CONVEYOR_FOREMAN_DIR (the Foreman's launcher sets them) and CLAUDE_PROJECT_DIR (Claude Code's) name
# the real main checkout: a case that calls the engine with none of its own would read and write that checkout's state
# (issue 452). CONVEYOR_CARDS, where a shell or launcher exports it, names a machine's cards folder: a case that calls
# the engine with none of its own would take that folder's release lock, claims and live files, shared with every
# card that tests at the same time (caselocks.test.sh). Without it, a case's cards folder is beside its own main.
unset CARDCTL CONVEYOR_CARD_SETTINGS CONVEYOR_OPENCODE_GUARD CONVEYOR_CODEX_GUARD CONVEYOR_CARD_RULES CONVEYOR_CARD CONVEYOR_FOREMAN CLAUDE_CODE_SESSION_ID CONVEYOR_TEST_SLOTS \
  CONVEYOR_MAIN CONVEYOR_FOREMAN_DIR CLAUDE_PROJECT_DIR CONVEYOR_CARDS
# The Foreman's mark (the session it is) is never this machine's own.
export XDG_STATE_HOME=$T/state
# The loop asks for a weekly limit reading while a card runs: never Claude's own here; a case sets its own.
export CONVEYOR_LIMIT_CMD=false
# `serve` asks which models have no price (noprice(), lib/control.sh): here the answer fails, so no loop files an issue
# for the stub models the test pack lists; a case of that look sets its own.
export CONVEYOR_NOPRICE_CMD=false
# Codex's models cache (climodels(), lib/control.sh) is never this machine's own. The shared one is read-only: a case
# that writes a cache exports its own CODEX_HOME under $T/$CASE, as cases run side by side and one case's cache there
# changed the models another case's snapshot read (clis.test.sh).
export CODEX_HOME=$T/codex-home; mkdir -p "$CODEX_HOME"; chmod a-w "$CODEX_HOME"
# The same-file check before a pick (overlap(), lib/pick.sh) is never a model call here: it fails, so each issue is
# picked as it is. A case of that check sets its own (deps.test.sh).
export CONVEYOR_OVERLAP_CMD=false
# So is the judge of the rule Split large issues (splitcheck(), lib/slices.sh): a case of that rule sets its own
# (slices.test.sh).
export CONVEYOR_SPLIT_CMD=false
# setup looks for a local API proxy on no port of this machine's (findproxy(), lib/setup.sh): a proxy running here
# would make every setup case ask for --builder-route and --reviewer-route. A case of that search names its stub proxy's port.
export CONVEYOR_PROXY_PORTS=
# Nor does it find this machine's own API keys, in the environment or in the env of Claude Code's settings file
# (routekey(), lib/control.sh): one found would make every setup case ask the routes, and check the key with a real
# call. A case of the API route names its own settings file and stub API.
unset ANTHROPIC_API_KEY OPENAI_API_KEY
export CONVEYOR_CLAUDE_SETTINGS=$T/no-claude-settings.json
# The host file (the state folder, the terms file) is never this machine's own; a case writes its own, in a folder of
# its own (case_keep).
export XDG_CONFIG_HOME=$T/config
# An address is put together with AT, so this file holds none itself (the privacy check runs over it).
AT=@
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t${AT}example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t${AT}example.com
fail() { echo "FAIL [$CASE]: $*" >&2; exit 1; }
st() { jq -r "$1" "$ST/cards.jsonl"; }
# Fails naming each line of the records file the record check (jq/check.jq) refuses, with the field it refused. A case
# that proves a writer's line checks calls this, not `loop check`: that sets a refused line aside and still exits 0.
recok() { # <records file> <what wrote them>
  local bad
  bad=$(jq -Rrn -f "$SRC/jq/check.jq" < "$1") || fail "the record check did not run on the records of $2"
  [ -z "$bad" ] || fail "$2 wrote a record the check refuses: $(while IFS=$'\t' read -r l f; do
    printf '\nline %s: the field %s is not in check.jq or has a type it refuses: %s' "$l" "$f" "$(sed -n "${l}p" "$1" | cut -c1-400)"; done <<<"$bad")"
}
# A card's lines apart from the marks (deps, start, filed, pushed, issue): what a case reads when it lists the steps of the review rule.
NOMARK='(.step | IN("deps", "start", "filed", "pushed", "issue") | not)'
# The changed tests a card runs before it lands are $STUB/test-cmd, the test.command of main's pack (setup): it
# passes unless a case writes its own. The run of a card's failing cases on main (verdicts(): a worktree under
# cards/mainrun/) runs $STUB/mainrun-cmd, and with none passes, running nothing: a case that fails on a card is the card's
# to fix, as before main was asked, unless a case writes one. So does the run of a bug card's test files on main without
# the fix (bugproof(), in the same folder).
# A bug card's build, for a case of a bug card that goes on to review (one whose issue has the label `bug`): it fixes
# a.txt (one line more) and writes a.test.sh, which holds that a.txt has at least the lines it has with the fix, so the
# test fails on main's code without the fix, wherever main is (bugproof()). Without it the card is sent back to build
# and blocked, never reviewed.
provenbug() { echo 'echo two >> a.txt; echo "[ \$(wc -l < a.txt) -ge $(wc -l < a.txt) ]" > a.test.sh' > "$STUB/build"; echo 'bash a.test.sh' > "$STUB/mainrun-cmd"; }
# The checks of the Board's fix cards (fixcheck.test.sh, runcheck.test.sh): the engine as the loop loads it, in a shell
# of the case's main ($R), cards under the case's folder, with <commands> run there (eval); its output in run.out, its
# exit in $RC, the first line of what the review is shown (<worktree>.unfixed of $FXWT) in $WHY.
fx_in() { # <commands>
  ( export CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards
    . "$SRC/conveyor.sh" state-dir > /dev/null && eval "$(grep '^\. "\$HERE/lib/' "$SRC/commands/run.sh")" || exit 9
    names || exit 9
    eval "$1" ) > "$T/$CASE/run.out" 2>&1; RC=$?
  [ "$RC" != 9 ] || fail "the engine could not be loaded: $(cat "$T/$CASE/run.out")"
  # shellcheck disable=SC2034 # read by the cases of fixcheck.test.sh and runcheck.test.sh
  WHY=$(head -n 1 "$FXWT.unfixed" 2>/dev/null)
}
# Card c7's worktree on main ($FXWT), with <change> made in it and staged; main holds the <file> <content> pairs first.
fx_wt() { # <change> [<file> <content>]...
  local c=$1; shift
  while [ $# -gt 1 ]; do printf '%s\n' "$2" > "$R/$1"; git -C "$R" add "$1"; shift 2; done
  git -C "$R" commit -qm 'tests' || fail "main's files"
  FXWT=$T/$CASE/cards/c7
  git -C "$R" worktree add -q --detach "$FXWT" && (cd "$FXWT" && eval "$c") && git -C "$FXWT" add -A || fail "the card's change could not be staged"
}
loop() { CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards bash "$SRC/conveyor.sh" "$@"; }
# The tunables, models and checks are the pack's: a case changes them in main's pack, for the rest of the case
# (tune), or for one command (tuned).
tune() { jq "$@" "$R/.conveyor/project.json" > "$STUB/pack.new" && mv "$STUB/pack.new" "$R/.conveyor/project.json"; } # [jq options] <jq filter>
tuned() { # <jq filter> <command...>
  local rc; cp "$R/.conveyor/project.json" "$STUB/pack.was"; tune "$1"; shift; "$@"; rc=$?; mv "$STUB/pack.was" "$R/.conveyor/project.json"; return $rc
}
# The control record, the only home of the cap and the two seats' models: as setup seeds it (seed), or with one
# seat's model changed and its effort kept (seatset). The judge off, visible changes waiting for the owner's yes and
# a push after each landing are set here, not left to control-defaults.json (judge on, visible off, push off): a case
# turns them as it needs. The rule Split large
# issues is off (its default is shadow): a card's lines are those of today's cards; its cases (slices.test.sh) turn it on.
seed() {
  mkdir -p "$ST"
  echo '{"mode":"run","cap":5,"guard":null,"held":[],"order":[],"rules":{"P0":true,"P1":true,"P2":true,"followups":true,"push":true,"visible":true,"split":"off","never":[]},"model":{"model":"m","effort":"medium"},"reviewer":{"model":"x","effort":"medium"},"judge":null,"judgeOn":false,"start":"queue","startHeld":[],"startSeen":[]}' \
    > "$ST/control.json"
}
# The loop's turns, for a check that something did not happen: a case waits for turns the loop takes, not for seconds
# in which a busy machine's loop may have taken none. watchturns (after setup, before the loop starts) has every loop
# started from here on note the wait that ends each of its turns in $TURNS, a line holding its main checkout: the
# engine's own sleep is this function, which knows the wait by its caller (run(), conveyor.sh) and its length (the
# 0.1 s waits there are for a card being stopped). turns <n> [<main>] (default: $R) returns once that loop has begun <n>
# more of those waits; the turn between two of them ran whole after the call, so two are one whole turn at least.
# The machine's Conveyor (machineloop) notes the wait that ends each of its turns as a line `machine`: turns <n> machine.
# That wait is 1 s here, not its 5 s (MACHINE_POLL): a case waits for its turns, never for their seconds, and five
# seconds a turn made the machine's cases sit out a minute each.
watchturns() {
  export TURNS=$T/$CASE/turns; : > "$TURNS"
  sleep() { case ${FUNCNAME[1]:-} in run) [ "$1" = 0.1 ] || echo "${CONVEYOR_MAIN:-}" >> "$TURNS" ;; machineloop) echo machine >> "$TURNS"; set -- 1 ;; esac; command sleep "$@"; } # sleep: the engine's own, passed on as called
  export -f sleep
}
turns() { # <n> [<main>]
  local m=${2:-$R} n; n=$(( $(grep -cxF "$m" "$TURNS") + $1 ))
  wait_until "[ \"\$(grep -cxF '$m' '$TURNS')\" -ge $n ]" || fail "the loop of $m did not take $1 more turns"
}
seatset() { jq -c --arg k "$1" --arg m "$2" '.[$k].model = $m' "$ST/control.json" > "$STUB/c.new" && mv "$STUB/c.new" "$ST/control.json"; } # <model|reviewer> <model>
GO=$'USER-VISIBLE: no\nVERDICT: GO'
NOGO=$'[P1] a.txt:1 wrong word\nNEW CARD: b.txt is stale\nUSER-VISIBLE: no\nVERDICT: NO-GO'
NOGO3=$'[P0] a.txt:1 wrong word\nb.txt:22 no mark here\n[P2] c.txt:3 a nit\nNEW CARD: b.txt is stale\nUSER-VISIBLE: no\nVERDICT: NO-GO'
# A review with each finding moved to other lines (a.txt:1 becomes a.txt:<k>1): the review of round <k> in a case
# whose rounds must not repeat a finding (one that comes back after its fix round ends the loop early).
moved() { sed -E "s/\.txt:([0-9]+)/.txt:$1\1/g" <<<"$2"; } # <k> <review>

setup() { # <issues json>: a fresh main repo, the three stubs, one billing and one prism ruling
  export R=$T/$CASE/main STUB=$T/$CASE/stub ST
  # The fixture of this run, copied (fixture, below). Merged into what the case may have made there before.
  mkdir -p "$R" "$STUB" "$T/$CASE/origin" && cp -a "$FIXTURE/main/." "$R/" && cp -a "$FIXTURE/stub/." "$STUB/" \
    && cp -a "$FIXTURE/origin/." "$T/$CASE/origin/" && git -C "$R" remote set-url origin "$T/$CASE/origin" \
    || fail "the run's fixture could not be copied into the case's folder"
  # The state folder, as every reader finds it: with no host file (a case writes one into its own folder before
  # setup, if any), it is the checkout's conveyor/state (lib/paths.sh), and asking the engine cost each case 0.08 s.
  if [ -e "${XDG_CONFIG_HOME:-$HOME/.config}/conveyor/host.json" ]; then ST=$(loop state-dir); else ST=$R/conveyor/state; fi
  # The project pack: the test pack (lib/test-pack.json, no checks) with its own card rules and hooks
  # (lib/test-card-rules.md, lib/test-hooks.json, in the fixture), never this repo's .conveyor/, the stub as its test command, the case's stub's ruling log, the stub models m and x allowed, a live record every
  # 0.2 s, no wait for GitHub to close an issue, no pause before a review with no verdict runs again, a made-up owner,
  # Dana, each card landing alone (landBatch 1: a case of batches, tests/batch.test.sh, turns them on), and no monthly
  # test-speed survey (a `serve` run at 03:00 on the 1st would file one: tests/survey.test.sh turns it on).
  jq --arg l "$STUB/rulings" '.test.command = "case $PWD in */mainrun/*) [ ! -f \"$STUB/mainrun-cmd\" ] || . \"$STUB/mainrun-cmd\" ;; *) . \"$STUB/test-cmd\" ;; esac" | .test.survey = false | .rulings.log = $l | .owner.name = "Dana" | .landBatch = 1
      | .models.allowed.claude += ["m"] | .models.allowed.codex += ["x"] | .tunables += {live: 0.2, closeWait: 0, reviewPause: 0}' \
    "$SRC/lib/test-pack.json" > "$R/.conveyor/project.json"
  filemode
  seed
  echo "$1" > "$STUB/issues.json"; PATH=$STUB:$PATH
}
# The per-file fixture, every case's, as a card runs each test file alone (tests(), lib/testrun.sh): main commits
# a.txt's stub test file a.test.sh and .conveyor/test-links.json linking a.txt to it, and pushes them; the pack's
# test.fileCommand is the stub $STUB/file-cmd (the test command setup gives: $STUB/mainrun-cmd on main, else
# $STUB/test-cmd), and test.command is that stub too. push.check is false, so a landing runs no linked test before its
# push (a case of that check turns it on). So a card that changes a.txt runs a.test.sh alone, through test.fileCommand.
filemode() {
  echo 'case $PWD in */mainrun/*) [ ! -f "$STUB/mainrun-cmd" ] || . "$STUB/mainrun-cmd" ;; *) . "$STUB/test-cmd" ;; esac' > "$STUB/file-cmd"
  echo '# The stub test file of a.txt: the pack'"'"'s test.fileCommand runs $STUB/file-cmd for it.' > "$R/a.test.sh"
  git -C "$R" add a.test.sh || fail "main's stub test file a.test.sh could not be staged"
  linkset '{"a.txt": ["a.test.sh"]}'
  tune '.test.fileCommand = ". \"$STUB/file-cmd\"" | .push.check = false | .test.command = .test.fileCommand'
}
# Main's committed test links (.conveyor/test-links.json, which the fixture's .gitignore leaves out, so added by
# force) set to <json>, committed with anything staged and pushed: after setup, a case's links of its own.
linkset() { # <links json>
  echo "$1" > "$R/.conveyor/test-links.json" && git -C "$R" add -f .conveyor/test-links.json && git -C "$R" commit -qm 'test links' \
    && git -C "$R" push -q origin main || fail "main's test links could not be set to $1"
}
# The fixture every case's setup copies (cp -a), made once per run, as this file is read, in $FIXTURE: main's repo
# (a.txt and .gitignore committed, its pack's card rules and hooks, untracked), origin (a bare repo main is pushed to)
# and the stubs. Made afresh by each case it cost the case about 0.15 s; copied, about 0.03 s. Nothing in it names its
# own folder: the stubs find the case's by $STUB and $R, and setup points main's origin at the case's own.
fixture() { # <folder>
  local R=$1/main STUB=$1/stub
  mkdir -p "$R/.claude/metrics" "$R/.conveyor" "$STUB" || return 1
  git -C "$R" init -q -b main; echo one > "$R/a.txt"
  cp "$SRC/lib/test-card-rules.md" "$R/.conveyor/card-rules.md"; cp "$SRC/lib/test-hooks.json" "$R/.conveyor/hooks.json"
  # The pack is left untracked, so a case that changes it (tune) leaves main's checkout clean.
  printf 'conveyor/\n.conveyor/\n' > "$R/.gitignore"; git -C "$R" add -A; git -C "$R" commit -qm init || return 1
  # The loop pushes each landing: origin is a bare repo beside main.
  git init -q --bare -b main "$1/origin"; git -C "$R" remote add origin "$1/origin"; git -C "$R" push -q origin main || return 1
  echo 'echo two >> a.txt' > "$STUB/build"
  # $STUB/move ("<line> <subject>"): the next test run sets main's a.txt to that line, so a card's landing conflicts
  # after its review (main moving before a review or landing is caught there, not at the landing).
  echo 'echo x >> "$STUB/tests"; [ ! -e "$STUB/move" ] || { read -r l m < "$STUB/move"; rm "$STUB/move"; echo "$l" > "$R/a.txt"; git -C "$R" commit -qam "$m"; }' > "$STUB/test-cmd"
  printf '%s\n' '{"id":"r-1","question":"billing export rule?","answer":"yes"}' '{"id":"r-2","question":"prism rule?","answer":"no"}' > "$STUB/rulings"
  cat > "$STUB/gh" <<'EOF'
#!/usr/bin/env bash
# The open issues; with $STUB/list-filed, the follow-ups filed so far are among them, as on GitHub.
issues() { jq -cs '.[0] + .[1:]' "$STUB/issues.json" $([ ! -e "$STUB/list-filed" ] || ls "$STUB/filed" 2>/dev/null); }
# A label made (gh label create): kept in $STUB/labels, never taken for an issue filed.
[ "$1" != label ] || { printf '%s\n' "$*" >> "$STUB/labels"; exit 0; }
case $2 in
  list) if [ "$4" = closed ]; then echo "$*" >> "$STUB/closed-asked"; [ ! -e "$STUB/closed-fail" ] || exit 1; cat "$STUB/closed-issues.json" 2>/dev/null || echo '[]'; else [ ! -f "$STUB/list-cmd" ] || . "$STUB/list-cmd"
    if [ "$4" = all ]; then issues | jq -c "sort_by(-.number) | .[:$6]"; else issues | jq -c ".[:$6]"; fi; fi ;; # all: newest first, as on GitHub
  # Another repository's issue (gh issue view <n> --repo <owner/repo> --json state): $STUB/repo.<owner_repo>.<n> holds
  # its state, else CLOSED; with $STUB/repo-fail.<owner_repo>, that repository cannot be read.
  view) case "$*" in *' --repo '*) k=${5//\//_}; [ ! -e "$STUB/repo-fail.$k" ] || { echo "GraphQL: Could not resolve to a Repository with the name '$5'. (repository)" >&2; exit 1; }
      echo "{\"state\":\"$(cat "$STUB/repo.$k.$3" 2>/dev/null || echo CLOSED)\"}" ;;
    *'--json closed'*) echo "$3" >> "$STUB/closed-viewed"; [ ! -e "$STUB/closed-fail" ] || exit 1
      jq -c --argjson n "$3" '{closed: any(.[]; .number == $n)}' "$STUB/closed-issues.json" 2>/dev/null || echo '{"closed":false}' ;;
    # closedAt: $STUB/closedAt.<n>, else "" (a closed issue whose closing time GitHub did not give).
    *'--json state'*) echo "{\"state\":\"$(cat "$STUB/state.$3" 2>/dev/null || cat "$STUB/state" 2>/dev/null || echo CLOSED)\",\"closedAt\":\"$(cat "$STUB/closedAt.$3" 2>/dev/null)\"}" ;;
    *) issues | jq --argjson n "$3" '.[] | select(.number == $n)' ;; esac ;;
  # gh api graphql: who opened each open issue (an issue's authorAssociation, else OWNER) and its parent and sub-issues
  # ($STUB/subs: a line "<parent> <part>" for each; a part not among the open issues is closed), or when the
  # awaiting-deploy labels were added.
  graphql) case "$*" in *authorAssociation*) s=$(jq -cRn '[inputs | split(" ") | map(tonumber)]' "$STUB/subs" 2>/dev/null) || s='[]'
      issues | jq -c --argjson s "${s:-[]}" 'map(.number) as $open | {data: {repository: {nameWithOwner: "o/r", issues: {nodes: map(.number as $n | {number, authorAssociation: (.authorAssociation // "OWNER"),
        parent: ([$s[] | select(.[1] == $n) | {number: .[0], repository: {nameWithOwner: "o/r"}}] | first),
        subIssues: {nodes: [$s[] | select(.[0] == $n) | {number: .[1], state: (if .[1] | IN($open[]) then "OPEN" else "CLOSED" end), repository: {nameWithOwner: "o/r"}}]}}),
        pageInfo: {hasNextPage: false, endCursor: null}}}}}' ;;
      *) [ ! -f "$STUB/labelled" ] || cat "$STUB/labelled" ;; esac ;;
  # gh api .../issues/<p>/sub_issues -F sub_issue_id=<id>: "<p> <part>" added to $STUB/subs (the part's id is
  # 1000000 + its number); gh api .../issues/<n>: that issue's id.
  repos/*/sub_issues) p=${2%/sub_issues}; p=${p##*/}; for a; do [[ $a != sub_issue_id=* ]] || echo "$p $((${a#*=} - 1000000))" >> "$STUB/subs"; done ;;
  repos/*/issues/*) echo "{\"id\": $((${2##*/} + 1000000))}" ;;
  # gh auth token: the token gh holds, read without the network (none, with gh's error text, with $STUB/signed-out;
  # timed out, exit 124 as `timeout` gives, with $STUB/token-timeout; an empty token with $STUB/token-empty). gh auth status: the
  # network check, which fails with $STUB/signed-out, and times out (as a GitHub that does not answer) with $STUB/unreached.
  token) [ ! -e "$STUB/token-timeout" ] || exit 124; [ ! -e "$STUB/token-empty" ] || exit 0; [ ! -e "$STUB/signed-out" ] || { echo 'no oauth token found for github.com' >&2; exit 1; }; echo gho_stub ;;
  status) [ ! -f "$STUB/status-cmd" ] || . "$STUB/status-cmd"; [ ! -e "$STUB/unreached" ] || exit 124; [ ! -e "$STUB/signed-out" ] ;;
  comment) [ ! -f "$STUB/comment-cmd" ] || . "$STUB/comment-cmd"; shift 2; printf '%s\n' "$*" >> "$STUB/comments" ;;
  close) echo "$3" >> "$STUB/closed"; shift 3; printf '%s\n' "$*" >> "$STUB/close-comments" ;;
  create) shift 2; n=$((100101 + $(cat "$STUB/filed" 2>/dev/null | wc -l))); l=(); m=
    [ ! -f "$STUB/create-cmd" ] || . "$STUB/create-cmd"
    while [ $# -gt 0 ]; do case $1 in --title) t=$2 ;; --body) b=$2 ;; --label) l+=("$2") ;; --milestone) m=$2 ;; esac; shift 2; done
    jq -cn --argjson n "$n" --arg t "$t" --arg b "$b" --arg m "$m" '{number:$n,title:$t,body:$b,milestone:(if $m == "" then null else {title:$m} end),
      createdAt:"2026-12-01",labels:($ARGS.positional|map({name:.}))}' --args "${l[@]}" >> "$STUB/filed"
    echo "https://github.com/o/r/issues/$n" ;;
esac
EOF
  # `--version` (doctor's requirement check, lib/requires.sh) is no session: the stubs answer it as the CLIs do.
  cat > "$STUB/claude" <<'EOF'
#!/usr/bin/env bash
[ "${1:-}" != --version ] || { echo '2.1.322 (Claude Code)'; exit 0; }
cat > "$STUB/brief"; echo "$*" >> "$STUB/sessions"; . "$STUB/build"
echo '{"type":"result","is_error":false,"usage":{"input_tokens":10,"cache_creation_input_tokens":20,"cache_read_input_tokens":999,"output_tokens":5}}'
EOF
  # `codex debug models` (the host's report, hostclis) is no review: the stub lists no models, as a Codex that offers no list.
  cat > "$STUB/codex" <<'EOF'
#!/usr/bin/env bash
[ "${1:-}" != debug ] || exit 1
[ "${1:-}" != --version ] || { echo 'codex-cli 0.130.0'; exit 0; }
while [ $# -gt 0 ]; do [ "$1" = -o ] && out=$2; shift; done
cat > /dev/null; echo x >> "$STUB/reviews"; [ ! -f "$STUB/review-cmd" ] || . "$STUB/review-cmd"; cat "$STUB/review.$(wc -l < "$STUB/reviews")" > "$out" || exit 1
echo '{"type":"turn.completed","usage":{"input_tokens":100,"cached_input_tokens":60,"output_tokens":7}}'
EOF
  # An OpenCode that lists no models and runs nothing (a case that runs one writes its own): the host's own, found
  # otherwise, is asked `opencode models` before every seat starts (hostclis), and can take its whole timeout to answer.
  printf '#!/usr/bin/env bash\nexit 1\n' > "$STUB/opencode"
  chmod +x "$STUB/gh" "$STUB/claude" "$STUB/codex" "$STUB/opencode"
}
# FIXTURE is named once, here: a case that runs a case of its own under another scratch folder (machine.test.sh
# t_machineleft: T=$d/in) copies this run's fixture, as $T/fixture is none there.
FIXTURE=$T/fixture; fixture "$FIXTURE" || { echo "the engine cases' fixture could not be made in $FIXTURE" >&2; exit 1; }
# A fixture only some cases copy (install.test.sh's code repo, setup.test.sh's sample), made once per run by the first
# case that asks for it, in $FIXTURE.<name> (a link to the folder <make> <folder> filled), and copied by every case
# after it. Two cases that ask at once may each make one: the first to link its folder wins, the other's is dropped,
# so each case copies a whole one, never one still being made. Not made in a run that has no case asking.
template() { # <name> <make>
  local t=$FIXTURE.$1 b=$FIXTURE.$1.$BASHPID
  [ ! -e "$t" ] || return 0
  rm -rf "$b"; "$2" "$b" || { rm -rf "$b"; return 1; }
  ln -s "${b##*/}" "$t" 2>/dev/null || rm -rf "$b"
  [ -e "$t" ]
}
issue() { # <number> <created> <label>...: an open issue as asked() gives it, opened by the owner
  local n=$1 d=$2; shift 2
  jq -cn --argjson n "$n" --arg d "$d" '{number:$n,title:"title \($n)",body:"body of \($n)",milestone:null,createdAt:$d,labels:($ARGS.positional|map({name:.})),authorAssociation:"OWNER"}' --args "$@"
}
landed() { # <issue> [follow-ups json]: the landed line of an earlier card for that issue
  jq -cn --argjson n "$1" --argjson f "${2:-null}" '{card:"c0-\($n)",issue:$n,step:"landed",time:"2026-11-01T00:00:00Z",tokens:{claude:0,codex:0},result:"ok",sha:"abc",reason:"",product:false}
    + if $f then {leftover:true,followups:$f} else {} end'
}

# Cases run several at a time, the slowest first (one after another the file ran past its 300 s budget; the runner
# starts one for each test slot it gets); each has its own $T/$CASE. A
# case's output, its ok line included, is printed whole under one lock when it ends, so two cases never interleave,
# and a red case hides no later one. The slot the runner took for the case is held by this process, the case and all
# the case starts, on the slot's core (slot_mine): it comes back when the last of them has ended, each however it ends.
# A process the case leaves that closed the slot's descriptor still keeps the slot: a process started before the case
# holds it until the case and all it left have ended (slot_watch), so it does whenever and however this process ends.
# The case runs in a shell of its own, given this one's variables, functions and options down a pipe.
# That shell is the case's keeper (case_keep): it starts the case, writes its exit status, and then ends every
# process the case left before the case is reported (case_end): a loop a case started in the background
# (`conveyor.sh machine`, `serve`, `run`) and did not stop, its exit trap not run, wrote on for hours to a file of the
# deleted scratch folder, until /tmp was full. On Linux the case's keeper is the child subreaper of all the case
# starts (prctl, set through python3 and kept by the bash it then becomes), so a process left with
# no parent, whatever group or session it made and whatever it took out of its environment, is the keeper's own
# child; a case whose keeper cannot be made that does not start. Elsewhere (macOS) no process can be made that: the
# processes left are those under the keeper, those of the case's process group, and those that are in no group of the
# case's but still carry its mark, name its scratch folder or have a file of the case open (case_far).
# The case's keeper is a process group of its own (set -m, for its start alone), so a signal to the runner's
# group, one that cannot be caught too (KILL), does not end it: it ends the case the same way when
# this worker is gone, as it does when this worker is told to end (the runner passes its own TERM on) and tells that
# group to. A process that outlives the case's keeper (the keeper was killed outright) keeps the slot while it is in
# the keeper's group or carries the case's mark (slot_watch).
run_case() {
  local k='' s w mark='' end t0 sub=() CASE_WORKER=$BASHPID CASE_MARK=CONVEYOR_TEST_CASE_ID=$BASHPID.$RANDOM$RANDOM
  local CASE_LIMIT=${CASE_LIMITS[$CASE]:-} # its file's `# timeout:` line (the runner), for its keeper (case_keep)
  slot_mine
  exec {w}> >(slot_watch "$CASE_MARK" > /dev/null 2>&1)
  # In a loop's test step, the case is named as running from here until it ends (conveyor.sh testcases()), so the
  # loop's health names a case that hangs while the others go on; once it ends, as done (below).
  [ ! -d "${CONVEYOR_TEST_LOG:-}" ] || { mark=$CONVEYOR_TEST_LOG/cases/$CASE; mkdir -p "${mark%/*}" && : > "$mark"; }
  # python3 starts with SIGPIPE and SIGXFSZ ignored, and what it becomes would start every program of the case so: a
  # `grep | head` whose grep is to end on the closed pipe would write an error and go on. Each is as this worker has
  # it.
  [ "$(uname -s)" != Linux ] || sub=(python3 -I -c 'import ctypes, os, signal, sys
if ctypes.CDLL(None).prctl(36, 1): sys.exit(1)  # PR_SET_CHILD_SUBREAPER
ign = int(next(l for l in open("/proc/%s/status" % sys.argv[1]) if l.startswith("SigIgn")).split()[1], 16)
for s in signal.SIGPIPE, signal.SIGXFSZ:
    if not ign >> (s - 1) & 1: signal.signal(s, signal.SIG_DFL)
os.execvp(sys.argv[2], sys.argv[2:])' "$BASHPID")
  trap 'trap "" TERM INT HUP; [ -z "$k" ] || { kill -TERM -- "-$k" 2>/dev/null; wait "$k"; }; exit 143' TERM INT HUP
  exec {s}< <(declare -p; declare -f; set +o)
  t0=${EPOCHREALTIME//[!0-9]/}; times > "$T/$CASE.cpu"
  # 2>/dev/null: the variables that are the shell's own, and read-only, refuse to be set again.
  set -m; ( set +m; echo "$BASHPID" >&"$w"; exec "${sub[@]}" bash -c '. "/dev/fd/$1" 2>/dev/null; eval "exec $1<&-"; case_keep' "$0" "$s" ) > "$T/$CASE.keeper" 2>&1 < /dev/null & k=$!; set +m
  exec {s}<&-
  wait "$k"
  # Its own time in microseconds, its keeper's start to its end, and this worker's children's user and system times
  # (`times`) before and after, its keeper's tree, each process counted as it is waited for, for its
  # file's time and CPU seconds (case_times()). The keeper reaps what the case left on Linux alone, where it is their subreaper.
  echo $(( ${EPOCHREALTIME//[!0-9]/} - t0 )) > "$T/$CASE.sec"; times >> "$T/$CASE.cpu"
  exec {w}>&-
  # A case that ended is named in cases/ok or cases/failed before its running mark goes (conveyor.sh watch()), so the
  # loop's live record counts the cases done and failed while the run goes on.
  # One stopped at its limit (case_keep) is named in cases/timedout too, before it is named failed: a release's result
  # says "timed out" for it (fulltest.sh suiteprog()).
  [ -z "$mark" ] || [ ! -e "$T/$CASE.late" ] || { mkdir -p "${mark%/*}/timedout" && : > "${mark%/*}/timedout/$CASE"; }
  [ -z "$mark" ] || { end=failed; [ "$(cat "$T/$CASE.rc" 2>/dev/null)" != 0 ] || end=ok; mkdir -p "${mark%/*}/$end" && : > "${mark%/*}/$end/$CASE"; rm -f "$mark"; }
  [ -e "$T/$CASE.rc" ] || echo "FAIL [$CASE]: the case's keeper did not start, or was ended before the case was: $(cat "$T/$CASE.keeper" 2>/dev/null)" >> "$T/$CASE.out"
  [ "$(cat "$T/$CASE.rc" 2>/dev/null)" != 0 ] || echo "ok $CASE" >> "$T/$CASE.out"
  flock "$T/print.lock" cat "$T/$CASE.out"
}
# The time of each case file <file>... whose every case the run selected (SEL) and timed (run_case: $T/<case>.sec and
# $T/<case>.cpu), one a line, `<file's name><TAB><seconds><TAB><CPU seconds>`: the sums of its cases' own times, as
# they run at once and the run's time is no one file's. For the times the loop records of a test file (README.md, The
# test step; the runner, CONVEYOR_TEST_TIMES).
case_times() { # <case file>...
  local f c x u m n
  for f; do
    u=0; m=0; n=''
    for c in $(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$f"); do
      case " $SEL " in *" $c "*) ;; *) n=''; break ;; esac
      { read -r x < "$T/$c.sec"; } 2>/dev/null && [[ $x =~ ^[0-9]+$ ]] && case_cpu "$T/$c.cpu" || { n=''; break; }
      u=$((u + x)); m=$((m + CASE_CPU)); n=1
    done
    [ -z "$n" ] || printf '%s\t%d.%d\t%d.%d\n' "${f##*/}" $((u / 1000000)) $((u % 1000000 / 100000)) $((m / 1000)) $((m % 1000 / 100))
  done
}
# A case's CPU milliseconds, into CASE_CPU (no subshell: the runner calls it for every case after its last ends): in
# <file>, two outputs of `times` (run_case), the second line of each the children's user and system times
# (`<m>m<s>.<ms>s`, the point the locale's); the second's sum less the first's.
case_cpu() { # <file>
  local l i=0 w s=0
  [ -r "$1" ] || return 1
  while read -r l; do
    i=$((i + 1)); [ $i = 2 ] || [ $i = 4 ] || continue
    for w in $l; do
      [[ $w =~ ^([0-9]+)m([0-9]+)[.,]([0-9]{3})s$ ]] || return 1
      w=$(( (10#${BASH_REMATCH[1]} * 60 + 10#${BASH_REMATCH[2]}) * 1000 + 10#${BASH_REMATCH[3]} ))
      if [ $i = 2 ]; then s=$((s - w)); else s=$((s + w)); fi
    done
  done < "$1"
  [ $i = 4 ] && CASE_CPU=$s
}
# The keeper of one case (run_case), in a shell of its own. The case is a process group of its own (what it starts in
# the background stays in it), with the case's mark in its environment. A watcher tells the keeper to end when the
# worker that started it is gone.
case_keep() {
  local p='' watch timer='' rc
  trap 'trap "" TERM INT HUP; [ -z "$p" ] || case_end "$p"; exit 143' TERM INT HUP
  ( while kill -0 "$CASE_WORKER" 2>/dev/null; do
      command sleep 0.5
    done; kill -TERM $$ ) > /dev/null 2>&1 & watch=$!
  # Without the runner's test log: a case that runs a case of its own (run_case: t_machineleft) is one case of the run,
  # and its inner one is not named in the run's records (cases/, conveyor.sh watch()).
  # Each case has a host file folder of its own: a case that wrote its host file into one the cases shared (t_codexbuild:
  # a pool of one slot, testSlotsDir its own) gave every case's loop after it that pool, which held no slot of theirs,
  # and each card's test step waited for that one slot, "1 of 1 in use", for ever (the owner, 2026-11-14).
  # It starts in its own folder, never the runner's, which may be a checkout (gitfence, above).
  set -m; ( set +m; export "${CASE_MARK?}" XDG_CONFIG_HOME=$T/$CASE/config; unset CONVEYOR_TEST_LOG
    { mkdir -p "$T/$CASE" && cd "$T/$CASE"; } || { echo "FAIL [$CASE]: the case's folder $T/$CASE could not be made" >&2; exit 1; }
    "t_$CASE" ) > "$T/$CASE.out" 2>&1 & p=$!; set +m
  # Its limit (CASE_LIMIT: its file's `# timeout:` line, run_case): past it, the case's group is told to end and
  # killed 3 s later, and the case fails as timed out ($T/$CASE.late), its exit 124. The others go on.
  [ -z "${CASE_LIMIT:-}" ] || { ( z=''; trap '[ -z "$z" ] || kill "$z" 2>/dev/null; exit 0' TERM
      command sleep "$CASE_LIMIT" & z=$!; wait "$z" # sleep: the case's time limit
      : > "$T/$CASE.late"; kill -TERM -- "-$p" 2>/dev/null
      command sleep 3 & z=$!; wait "$z"; kill -KILL -- "-$p" 2>/dev/null ) > /dev/null 2>&1 & timer=$!; } # sleep: the grace after TERM
  wait "$p"; rc=$?
  [ -z "$timer" ] || { kill "$timer" 2>/dev/null; wait "$timer" 2>/dev/null; }
  [ ! -e "$T/$CASE.late" ] || { rc=124; echo "FAIL [$CASE]: timed out after $CASE_LIMIT s (its file's # timeout: line); the case and its process group were stopped" >> "$T/$CASE.out"; }
  echo "$rc" > "$T/$CASE.rc"
  kill "$watch" 2>/dev/null; wait "$watch" 2>/dev/null
  case_end "$p"; exit 0
}
below() { local k; echo "$1"; for k in $(pgrep -P "$1"); do below "$k"; done; } # <pid>: it and every process under it
# case_kids <the asking $( )'s own BASHPID>: the keeper's children that still run, but that one.
case_kids() { ps -axo pid=,ppid=,stat= | awk -v p=$$ -v me="$1" '$2 == p && $1 != me && $3 !~ /^Z/ { print $1 }'; }
# The processes that are the case's by what they carry, wherever they are (no parent, a session of their own): those
# with the case's mark in their environment (every program the case started and every one those started, where they
# kept it), those whose environment or command names the case's scratch folder (a program started after the case's
# setup has it in its PATH, a loop in its CONVEYOR_MAIN: one that took the mark out still has those), and those whose
# working folder is in it (one started there with an empty environment). A loop left by a case is one of them
# whatever it changed: it finds the case's checkout by one of the three. The rows are matched in this shell: a
# search started for the mark or the folder would carry it itself.
# One with an empty environment, started outside the scratch folder (a daemon with an environment of its own:
# Python's subprocess with env={}), carries none of the three. It is found by a file it has open: one in the scratch
# folder, or the case's output file ($T/$CASE.out), which is the error output of every program the case starts and
# of each one those start that did not point its own elsewhere. Only what a process holds of the case makes it the
# case's: one that merely began while the case ran, with no parent and no environment, may be anyone's, and is left.
# So one that kept none of these (no mark, no folder, every descriptor closed or pointed elsewhere) is not found.
case_far() {
  local pid a d=$T/$CASE r
  r=$(cd "$T" 2>/dev/null && pwd -P)/$CASE || r=$d
  while read -r pid a; do
    [[ " $a " != *" $CASE_MARK "* && $a != *"$d/"* && $a != *"$r/"* ]] || echo "$pid"
  done < <(ps axeww -o pid=,args=)
  while read -r a; do
    case $a in p*) pid=${a#p} ;; n"$r"|n"$r"/*|n"$r.out") echo "$pid" ;; esac
  done < <(lsof -a -u "$UID" -Fpn 2>/dev/null)
}
# case_left <the case's process group>, asked in a $( ) of the keeper's own: every process the case left. Those under
# the keeper, which on Linux is all of them (the keeper is their subreaper); those of the case's group; and, where
# the keeper is no subreaper, those found by what they carry (case_far).
case_left() {
  local me=$BASHPID k
  { for k in $(case_kids "$me"); do below "$k"; done; pgrep -g "$1"
    [ "$(uname -s)" = Linux ] || case_far; } | sort -u
}
# case_end <the case's process group>: ends every process the case left: TERM, then KILL for those still there 3 s
# later by the clock. Counted in looks (30 of 0.1 s), the wait was each look's time too, a `ps` of the machine and a
# `pgrep` a process: 11 to 24 s on a busy machine for a process that ignores TERM (slots.test.sh t_slotcaseterm).
# Each child of the keeper is then stopped before the processes under it are listed and killed (wait_end), so
# it starts none unseen, again until the keeper has none: one left with no parent as its parent was killed is the
# keeper's child by then.
case_end() {
  local k left end=$(( ${EPOCHREALTIME//[!0-9]/} + 3000000 ))
  left=$(case_left "$1"); [ -n "$left" ] || return 0
  kill -TERM $left 2>/dev/null
  while [ -n "$(case_left "$1")" ] && [ "${EPOCHREALTIME//[!0-9]/}" -lt "$end" ]; do
    command sleep 0.1
  done
  while left=$(case_kids "$BASHPID"); [ -n "$left" ]; do for k in $left; do wait_end "$k"; done; done
  kill -KILL -- "-$1" $(case_left "$1") 2>/dev/null || :
}
