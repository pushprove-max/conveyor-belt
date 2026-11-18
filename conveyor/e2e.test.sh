#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# The end-to-end test (D4): Conveyor in a sample repo whose default branch is master, with gh, the builder (claude)
# and the reviewer (codex) stubbed on PATH. In order: a card lands for real, the loop pushes it for real to a local
# bare remote through the review gate, a card is blocked with its work kept, a retry lands that kept work, and the
# review gate refuses a push that carries a commit no card reviewed.
# The scenario runs once on the engine as it is, and must pass; then once per step on a copy of the engine with one
# break planted in that step, and each must fail at that step: a test that a break does not turn red tests nothing.
set -uo pipefail
SRC=$(cd "$(dirname "$0")" && pwd -P)
. "$SRC/lib/portable.sh"; p_tools
GATE=$SRC/../.claude/hooks/adversarial-review-gate.sh
T=$(mktemp -d); trap 'chmod -R u+w "$T"; rm -rf "$T"' EXIT
# A run inside a Conveyor card inherits the loop's own environment.
unset CONVEYOR_CARD_SETTINGS CONVEYOR_CARD_RULES
export CONVEYOR_LIMIT_CMD=false
# An address is put together with AT, so this file holds none itself (the privacy check runs over it).
AT=@
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t${AT}example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t${AT}example.com
GO=$'USER-VISIBLE: no\nVERDICT: GO'

# The scenario, in its own folder <dir>, run by the engine in <engine dir>. Prints `FAIL [<step>]: why` and exits 1
# at the first step that does not do what it should.
scenario() { # <dir> <engine dir>
  local D=$1 E=$2 STEP=setup R=$1/main STUB=$1/stub ST=$1/state old k sha before hand out
  fail() { echo "FAIL [$STEP]: $*"; exit 1; }
  loop() { CONVEYOR_MAIN=$R CONVEYOR_CARDS=$D/cards bash "$E/conveyor.sh" "$@"; }
  st() { jq -r "$1" "$ST/cards.jsonl"; }
  issue() { jq -cn --argjson n "$1" '[{number:$n,title:"title \($n)",body:"body of \($n)",milestone:null,createdAt:"2026-01-01",labels:[]}]' > "$STUB/issues.json"; }
  # The host file names the state folder, so none is made inside the engine the main checkout links to.
  export XDG_CONFIG_HOME=$D/config; mkdir -p "$XDG_CONFIG_HOME/conveyor" "$STUB" "$ST"
  jq -n --arg s "$ST" '{stateDir: $s}' > "$XDG_CONFIG_HOME/conveyor/host.json"
  echo '{"mode":"run","cap":1,"guard":null,"held":[],"order":[],"rules":{"P0":true,"P1":true,"P2":true,"followups":true,"push":true,"never":[]},"model":{"model":"m","effort":"medium"},"reviewer":{"model":"x","effort":"medium"},"start":"queue","startHeld":[],"startSeen":[]}' > "$ST/control.json"
  # The sample repo: default branch master, its remote a bare repo beside it. Its conveyor/ links to the engine, as a
  # project's checkout holds the plugin, so the review gate finds the card records through it.
  git init -q -b master "$R" && echo one > "$R/a.txt" && ln -s "$E" "$R/conveyor" && printf 'conveyor\n.conveyor/\n' > "$R/.gitignore" \
    && git -C "$R" add -A && git -C "$R" commit -qm init && git init -q --bare -b master "$D/origin" \
    && git -C "$R" remote add origin "$D/origin" && git -C "$R" push -q origin master || fail "the sample repo could not be made"
  mkdir -p "$R/.conveyor"; cp "$SRC/lib/test-card-rules.md" "$R/.conveyor/card-rules.md"; cp "$SRC/lib/test-hooks.json" "$R/.conveyor/hooks.json"
  jq --arg l "$STUB/rulings" '.defaultBranch = "master" | .linkFromMain = [] | .test.command = "true" | .rulings.log = $l
    | .models.allowed.claude += ["m"] | .models.allowed.codex += ["x"] | .tunables += {live: 0.2, closeWait: 0}' \
    "$SRC/lib/test-pack.json" > "$R/.conveyor/project.json"
  : > "$STUB/rulings"
  # The review gate, as a project's pre-push hook: every commit a push takes to the remote is one Conveyor landed
  # after its review, by the review gate's own list of them (adversarial-review-gate.sh --conveyor-reviewed).
  cat > "$R/.git/hooks/pre-push" <<EOF
#!/usr/bin/env bash
ok=\$(HOME="$D/home" bash "$GATE" --conveyor-reviewed < /dev/null | cut -d' ' -f1)
while read -r lref lsha rref rsha; do
  case \$rsha in *[!0]*) range=\$rsha..\$lsha ;; *) range=\$lsha ;; esac
  for c in \$(git rev-list "\$range"); do grep -qx "\$c" <<<"\$ok" || { echo "review gate: \$c has no review on record" >&2; exit 1; }; done
done
EOF
  chmod +x "$R/.git/hooks/pre-push"
  cat > "$STUB/gh" <<'EOF'
#!/usr/bin/env bash
case $2 in
  list) if [ "$4" = closed ]; then echo '[]'; else jq -c ".[:$6]" "$STUB/issues.json"; fi ;;
  view) case "$*" in *'--json state'*) echo '{"state":"CLOSED"}' ;; *) jq --argjson n "$3" '.[] | select(.number == $n)' "$STUB/issues.json" ;; esac ;;
  comment) shift 2; printf '%s\n' "$*" >> "$STUB/comments" ;;
  close) echo "$3" >> "$STUB/closed" ;;
esac
EOF
  # The builder runs $STUB/build in the card's worktree; the reviewer answers GO.
  printf '%s\n' '#!/usr/bin/env bash' 'cat > /dev/null; . "$STUB/build"' \
    'echo '\''{"type":"result","is_error":false,"usage":{"input_tokens":1,"cache_creation_input_tokens":1,"cache_read_input_tokens":1,"output_tokens":1}}'\' > "$STUB/claude"
  cat > "$STUB/codex" <<EOF
#!/usr/bin/env bash
while [ \$# -gt 0 ]; do [ "\$1" = -o ] && out=\$2; shift; done
cat > /dev/null; printf '%s\n' '$GO' > "\$out"
echo '{"type":"turn.completed","usage":{"input_tokens":1,"cached_input_tokens":1,"output_tokens":1}}'
EOF
  chmod +x "$STUB/gh" "$STUB/claude" "$STUB/codex"; export STUB PATH=$STUB:$PATH

  STEP=land; issue 1; echo 'echo landed > one.txt' > "$STUB/build"
  loop run > "$D/run.1" 2>&1 || fail "the run exited non-zero: $(tail -n 5 "$D/run.1")"
  sha=$(st 'select(.issue == 1 and .step == "landed") | .sha')
  [ -n "$sha" ] && [ "$sha" = "$(git -C "$R" rev-parse refs/heads/master)" ] && [ "$(git -C "$R" show master:one.txt 2>&1)" = landed ] \
    && git -C "$R" log -1 --format=%s master | grep -q '(#1)$' && [ -z "$(git -C "$R" status --porcelain)" ] \
    || fail "master is not the landed commit with the card's change, or its checkout is left dirty: $(st 'select(.issue == 1) | "\(.step) \(.result) \(.reason)"' | tr '\n' ,)"
  STEP=push
  [ "$(git -C "$D/origin" rev-parse refs/heads/master)" = "$sha" ] && [ -n "$(st 'select(.issue == 1 and .step == "pushed") | .sha')" ] \
    || fail "the landing did not reach the remote's master through the review gate: $(st 'select(.step | IN("push", "pushed")) | "\(.step) \(.result) \(.reason)"' | tr '\n' ,)"

  STEP=kept; issue 2; echo 'echo kept > kept.txt; exit 3' > "$STUB/build"
  loop run > "$D/run.2" 2>&1
  old=$(st 'select(.issue == 2 and .step == "blocked") | .card'); k=$ST/$(st 'select(.issue == 2 and .step == "blocked") | .kept')
  [ -n "$old" ] && grep -qx '+kept' "$k/$old.patch" 2>/dev/null && ! git -C "$R" cat-file -e master:kept.txt 2>/dev/null \
    || fail "the failed build was not blocked with its change kept as a patch: $(st 'select(.issue == 2) | "\(.step) \(.result) \(.reason)"' | tr '\n' ,)"

  STEP=retry; echo 'echo more > more.txt' > "$STUB/build"
  loop retry 2 > "$D/retry" 2>&1 || fail "retry of the blocked #2 exited non-zero: $(cat "$D/retry")"
  loop run > "$D/run.3" 2>&1 || fail "the run of the retried #2 exited non-zero: $(tail -n 5 "$D/run.3")"
  sha=$(st 'select(.issue == 2 and .step == "landed") | .sha')
  st 'select(.issue == 2 and .step == "worktree") | .reason' | grep -q "^resumed from the kept patch of card $old:" \
    && [ -n "$sha" ] && [ "$sha" = "$(git -C "$R" rev-parse refs/heads/master)" ] && [ "$(git -C "$R" show master:kept.txt 2>&1)" = kept ] \
    && [ "$(git -C "$R" show master:more.txt 2>&1)" = more ] && [ "$(git -C "$D/origin" rev-parse refs/heads/master)" = "$sha" ] \
    || fail "the retry did not land and push the kept work with its own: $(st 'select(.issue == 2) | "\(.step) \(.result) \(.reason)"' | tr '\n' ,)"

  # A commit made on master by hand, under the next landing: the loop's push carries it, and the gate refuses it.
  STEP=gate; before=$(git -C "$D/origin" rev-parse refs/heads/master)
  echo hand > "$R/hand.txt" && git -C "$R" add hand.txt && git -C "$R" commit -qm 'by hand' && hand=$(git -C "$R" rev-parse HEAD) || fail "the hand commit could not be made"
  issue 3; echo 'echo three > three.txt' > "$STUB/build"
  loop run > "$D/run.4" 2>&1 && fail "a run whose push carries an unreviewed commit exited zero"
  sha=$(st 'select(.issue == 3 and .step == "landed") | .sha')
  [ -n "$sha" ] && [ "$sha" = "$(git -C "$R" rev-parse refs/heads/master)" ] && [ "$(git -C "$D/origin" rev-parse refs/heads/master)" = "$before" ] \
    && st 'select(.step == "push" and .result == "fail") | .reason' | grep -q "review gate: $hand has no review on record" \
    || fail "the push of an unreviewed commit was not refused by the review gate: $(st 'select(.step | IN("push", "pushed")) | "\(.step) \(.result) \(.reason)"' | tr '\n' ,)"
  echo "ok: every step"
}

# One break per step, planted in a copy of the engine: <step>, the text it replaces, the text it puts there.
BREAKS=(
  land 'git update-ref -m "conveyor ${a[0]}"' 'true git update-ref -m "conveyor ${a[0]}"'
  push 'git push "$REMOTE" "$sha:refs/heads/$to"' 'git push --dry-run "$REMOTE" "$sha:refs/heads/$to"'
  kept '--no-renames > "$k/$1.patch" 2>/dev/null' '--no-renames > /dev/null 2>/dev/null'
  retry 'if git -C "$wt" apply --index "$fromk/$from.patch" 2>/dev/null; then' 'if false; then'
  gate 'git push "$REMOTE" "$sha:refs/heads/$to"' 'git push --no-verify "$REMOTE" "$sha:refs/heads/$to"'
)
( scenario "$T/engine" "$SRC" ) > "$T/engine.out" 2>&1 &
for ((i = 0; i < ${#BREAKS[@]}; i += 3)); do
  s=${BREAKS[i]} from=${BREAKS[i + 1]} to=${BREAKS[i + 2]}
  # Planted in the engine file that holds the text: conveyor.sh or one of its parts in lib/.
  mkdir -p "$T/$s" && cp -R "$SRC" "$T/$s/engine" && f=$(grep -lF -- "$from" "$T/$s/engine/conveyor.sh" "$T/$s/engine"/lib/*.sh | head -n 1)
  # A break whose text the engine no longer holds plants nothing: say so, rather than pass on an engine left whole.
  [ -n "$f" ] || { echo "the break for $s is not planted: the engine no longer holds: $from" > "$T/$s.out"; continue; }
  c=$(<"$f"); printf '%s\n' "${c/"$from"/"$to"}" > "$f"
  ( scenario "$T/$s" "$T/$s/engine" ) > "$T/$s.out" 2>&1 &
done
wait
rc=0
grep -qx 'ok: every step' "$T/engine.out" || { echo "FAIL: the scenario does not pass on the engine as it is:"; cat "$T/engine.out"; rc=1; }
for ((i = 0; i < ${#BREAKS[@]}; i += 3)); do
  s=${BREAKS[i]}
  [ "$(grep -m 1 '^FAIL \[' "$T/$s.out" | cut -d']' -f1)" = "FAIL [$s" ] \
    || { echo "FAIL: the break planted in step $s did not fail that step:"; cat "$T/$s.out"; rc=1; }
done
[ $rc != 0 ] || echo "ok e2e: every step passes, and fails when it is broken"
exit $rc
