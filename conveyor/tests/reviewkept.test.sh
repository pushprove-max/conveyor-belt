#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases: a Claude or OpenCode review that failed or reported no token usage, and a review that `control stop`
# ended with no price to read, keep their events and err in the card's kept folder (reviewkeep()), as a failed Codex
# review does (fail.test.sh).
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# rkcheck <what ran>: run.out's first line names the kept events file, and the kept folder of card c7-7 holds the
# events and err the review wrote ("rk-events" and "rk-err" in them).
rkcheck() {
  local k=$ST/kept/c7-7
  grep -qF rk-events "$k/c7-7.review.events" && grep -qF rk-err "$k/c7-7.review.err" \
    || fail "$1: the review's events or err were not kept in $k: $(ls "$k" 2>&1) $(cat "$T/$CASE/run.out")"
  [[ $(head -n 1 "$T/$CASE/run.out") == *'; its events are kept in c7-7.review.events'* ]] \
    || fail "$1: the reason does not name the kept events file: $(cat "$T/$CASE/run.out")"
}

# Bug: a failed Claude review never called reviewkeep(): its events and err went with the card (clean()), so why it
# failed could not be read. The stub spends tokens, so the failure is no "never started" one (nostart()).
t_reviewkeptclaude() {
  setup '[]'
  local s=('#!/usr/bin/env bash' 'cat > /dev/null'
    'echo "{\"type\":\"result\",\"is_error\":true,\"result\":\"rk-events\",\"usage\":{\"input_tokens\":3,\"output_tokens\":2}}"' 'echo rk-err >&2; exit 1')
  # stub: a Claude review that spent tokens, wrote events and stderr, and failed (the shared stub cannot fail a review)
  printf '%s\n' "${s[@]}" > "$STUB/claude"
  chmod +x "$STUB/claude"
  fx_in 'w=$CARDS/c7-7 && mkdir -p "$CARDS" && git -C "$MAIN" worktree add -q --detach "$w" && claudereview "$w" brief instructions m low'
  rkcheck "claudereview <worktree> brief instructions m low"
}
# Bug: as t_reviewkeptclaude, for a failed OpenCode review.
t_reviewkeptopencode() {
  setup '[]'
  local s=('#!/usr/bin/env bash' 'cat > /dev/null'
    'echo "{\"type\":\"step_finish\",\"timestamp\":1,\"sessionID\":\"rk-events\",\"part\":{\"type\":\"step-finish\",\"tokens\":{\"input\":3,\"output\":2,\"reasoning\":0,\"cache\":{\"read\":0,\"write\":0}}}}"' 'echo rk-err >&2; exit 1')
  # stub: an OpenCode review that spent tokens, wrote events and stderr, and failed (the shared stub cannot fail a review)
  printf '%s\n' "${s[@]}" > "$STUB/opencode"
  chmod +x "$STUB/opencode"
  fx_in 'w=$CARDS/c7-7 && mkdir -p "$CARDS" && git -C "$MAIN" worktree add -q --detach "$w" && opencodereview "$w" brief instructions prov/m low'
  rkcheck "opencodereview <worktree> brief instructions prov/m low"
}
# Bug: an OpenCode review that exited 0 with an answer but reported no token usage kept no events or err, so why
# its usage could not be read was lost with the card (clean()).
t_reviewkeptopencodenouse() {
  setup '[]'
  local s=('#!/usr/bin/env bash' 'cat > /dev/null'
    'echo "{\"type\":\"text\",\"sessionID\":\"rk-events\",\"part\":{\"text\":\"VERDICT: GO\"}}"' 'echo rk-err >&2; exit 0')
  # stub: an OpenCode review that answers and exits 0 but writes no step_finish usage (the shared stub reports usage)
  printf '%s\n' "${s[@]}" > "$STUB/opencode"
  chmod +x "$STUB/opencode"
  fx_in 'w=$CARDS/c7-7 && mkdir -p "$CARDS" && git -C "$MAIN" worktree add -q --detach "$w" && opencodereview "$w" brief instructions prov/m low'
  rkcheck "opencodereview <worktree> brief instructions prov/m low (exit 0, answer, no usage)"
}
# Bug: as t_reviewkeptopencodenouse, for a Claude review that answered with no token usage.
t_reviewkeptclaudenouse() {
  setup '[]'
  local s=('#!/usr/bin/env bash' 'cat > /dev/null'
    'echo "{\"type\":\"result\",\"is_error\":false,\"session_id\":\"rk-events\",\"result\":\"VERDICT: GO\"}"' 'echo rk-err >&2; exit 0')
  # stub: a Claude review that answers and exits 0 but writes no usage (the shared stub reports usage)
  printf '%s\n' "${s[@]}" > "$STUB/claude"
  chmod +x "$STUB/claude"
  fx_in 'w=$CARDS/c7-7 && mkdir -p "$CARDS" && git -C "$MAIN" worktree add -q --detach "$w" && claudereview "$w" brief instructions m low'
  rkcheck "claudereview <worktree> brief instructions m low (exit 0, answer, no usage)"
}
# Bug: `control stop` ended a Claude review before it wrote its usage: stopped() wrote an unpriced line, outkeep()
# keeps no review's files, and clean() then removed its events and err. stopped() and clean() are called as the loop
# calls them (run.sh) on a card whose last line starts its review.
t_reviewkeptstop() {
  setup '[]'
  for l in '{"step":"worktree","result":"ok"}' '{"step":"start","result":"","of":"review"}'; do
    jq -c '{card: "c7-7", issue: 7, time: "2026-11-01T00:00:00Z", tokens: {claude: 0, codex: 0}, sha: "", reason: ""} + .' <<<"$l" >> "$ST/cards.jsonl"
  done
  fx_in 'w=$CARDS/c7-7 && mkdir -p "$CARDS" && echo "{\"model\":\"claude-m\"}" > "$w.live" \
    && echo "{\"type\":\"system\",\"subtype\":\"init\",\"session_id\":\"rk-events\"}" > "$w.events" && echo rk-err > "$w.err" \
    && stopped c7-7 7 && clean "$w"; jq -r "select(.step == \"review\") | .reason" "$ST/cards.jsonl"'
  local k=$ST/kept/c7-7
  grep -qF rk-events "$k/c7-7.review.events" && grep -qF rk-err "$k/c7-7.review.err" \
    || fail "stopped c7-7 7 then clean: the stopped review's events or err were not kept in $k: $(ls "$k" 2>&1) $(cat "$T/$CASE/run.out")"
  grep -qxF 'stopped by control stop while it ran; its events are kept in c7-7.review.events' "$T/$CASE/run.out" \
    || fail "stopped c7-7 7: the stopped line's reason does not name the kept events file: $(cat "$T/$CASE/run.out")"
}
# rkstopnoevent <live model> [first attempt]: `control stop` ends a review on <live model> that wrote to stderr but no
# event yet; with [first attempt], the review runs again and that is its .firsttry (reviewed()). stopped() and clean()
# are called as the loop calls them (run.sh). Bug: stopped() returned on the empty events file before reviewkeep(), and
# clean() then removed the err that said why the review had not started.
rkstopnoevent() {
  setup '[]'
  for l in '{"step":"worktree","result":"ok"}' '{"step":"start","result":"","of":"review"}'; do
    jq -c '{card: "c7-7", issue: 7, time: "2026-11-01T00:00:00Z", tokens: {claude: 0, codex: 0}, sha: "", reason: ""} + .' <<<"$l" >> "$ST/cards.jsonl"
  done
  [ -z "${2:-}" ] || printf '%s\n' "$2" > "$T/$CASE/firsttry"
  fx_in "w=\$CARDS/c7-7 && mkdir -p \"\$CARDS\" && echo '{\"model\":\"$1\"}' > \"\$w.live\" \
    && { [ ! -s \"$T/$CASE/firsttry\" ] || cp \"$T/$CASE/firsttry\" \"\$w.firsttry\"; } \
    && : > \"\$w.events\" && echo rk-err > \"\$w.err\" && stopped c7-7 7 && clean \"\$w\""
  local k=$ST/kept/c7-7
  grep -qF rk-err "$k/c7-7.review.err" \
    || fail "stopped c7-7 7 then clean, a review on live model $1 with empty events, err rk-err and first attempt '${2:-none}': the err was not kept in $k: $(ls "$k" 2>&1) $(cat "$T/$CASE/run.out")"
}
t_reviewkeptstopnoeventclaude() { rkstopnoevent claude-m; }
t_reviewkeptstopnoeventopencode() { rkstopnoevent opencode:prov/m; }
t_reviewkeptstopnoeventcodex() { rkstopnoevent cx-1; }
# Bug: a review that ran again after a first attempt with a price and no verdict took the first-attempt branch, and
# that price skipped the keep at the end of stopped(): the second attempt's err went with clean(). Its stopped line
# names the kept file.
t_reviewkeptstopnoeventretry() {
  rkstopnoevent cx-1 '{"reason":"the review ended without one clear verdict","spent":{"model":"cx-1","tokens":{"codex":5},"usage":{"input":3,"output":2}}}'
  jq -r 'select(.step == "review") | .reason' "$ST/cards.jsonl" | grep -qxF 'stopped by control stop while it ran; its events are kept in c7-7.review.events' \
    || fail "stopped c7-7 7 after a first attempt with a price: the stopped line's reason does not name the kept file: $(grep '"review"' "$ST/cards.jsonl")"
}
