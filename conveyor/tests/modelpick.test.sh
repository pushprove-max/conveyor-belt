#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases (#763): the rule Pick settings (modelpick(), lib/modelpick.sh), the pick on a card's lines and the
# snapshot's table of picked cards by group and builder (cost.picks). Each case calls the engine's functions as card()
# calls them; only the shadow case runs a whole card, as only a card shows that each of its lines carries the pick and
# that its build still runs on the project's builder.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# Issue 7, which names one documentation file: under the pack's split thresholds and no pipeline file, so its group
# is "small docs". The rule is set as the owner sets it, by `control rules pick=shadow`.
picksetup() {
  setup "[$(issue 7 2026-01-01 | jq -c '.body = "Fix a typo in docs/guide.md."')]"
  loop control rules pick=shadow >/dev/null || fail "control rules pick=shadow was refused"
}

# Bugs caught: in shadow a card's lines did not carry its pick, or the rule changed the model that builds the card.
# A whole card (see the top): every line from its worktree to its landing carries the same pick, with its group and the
# project's builder (m, medium) as the choice, by auto; the build ran on that builder; the lines pass the record check.
# The pushed and issue lines are the push's, written after the card has ended, so they have none.
t_pickshadow() {
  picksetup; echo "$GO" > "$STUB/review.1"
  # Bug caught: a word the rule does not have was taken into the record.
  loop control rules pick=maybe >/dev/null 2>&1 && fail "control rules pick=maybe was taken"
  loop run 1 >/dev/null
  want='{"group":"small docs","choice":{"model":"m","effort":"medium"},"by":"auto","trial":false,"mode":"shadow"}'
  [ "$(st 'select(.step == "landed") | .issue')" = 7 ] || fail "the card did not land: $(st .step | tr '\n' ' ')"
  [ "$(jq -sc --argjson w "$want" '(map(.step) | index("worktree")) as $i | [.[$i:][] | select(.step | IN("push", "pushed", "issue") | not) | .pick == $w] | unique' "$ST/cards.jsonl")" = '[true]' ] \
    || fail "a line of the card from its worktree on does not carry its pick $want: $(st '[.step, .pick] | tostring' | tr '\n' ' ')"
  [ "$(st 'select(.step == "build") | "\(.model) \(.effort)"')" = 'm medium' ] || fail "the card did not build on the project's builder: $(st 'select(.step == "build")')"
  recok "$ST/cards.jsonl" "a picked card"
}

# Bug caught: the group did not follow the issue: an issue that names a pipeline file (the pack's pipelineFiles, a
# file under conveyor/lib/ here) was put with code, one at the split thresholds (three Done-when items,
# split.doneWhen 3) with small ones, or one with the label documentation with code. One fixture, one call an issue.
# Issue 11 names only the directory conveyor/lib/, in Markdown bold: a path with no extension that SPLITSIZE's files
# do not hold, and a "**" that onpipeline() kept as part of the name; it went into the code group (#825).
t_pickgroups() {
  setup "[$(issue 8 2026-01-01 | jq -c '.body = "Change conveyor/lib/run.sh."'),$(issue 9 2026-01-01 | jq -c '.body = "Change src/a.js.\n\nDone when:\n- one\n- two\n- three"'),$(issue 10 2026-01-01 documentation | jq -c '.body = "Change src/a.js."'),$(issue 11 2026-01-01 | jq -c '.body = "Change how the scripts in **conveyor/lib/** log."')]"
  tune '.split.doneWhen = 3 | .pipelineFiles = ["conveyor/lib/"]'
  loop control rules pick=on >/dev/null || fail "control rules pick=on was refused"
  fx_in 'for n in 8 9 10 11; do SEATCARD=$n PICK=""; modelpick c1-$n $n; jq -r "\"\(.group) \(.mode)\"" <<<"$PICK"; done'
  [ "$(cat "$T/$CASE/run.out")" = $'small pipeline on\nlarge code on\nsmall docs on\nsmall pipeline on' ] || fail "the groups of a pipeline, a large, a documentation and a pipeline-directory issue: $(cat "$T/$CASE/run.out")"
}

# Bug caught: a card whose builder the owner set was recorded as the rule's choice, or the pick moved its builder off
# the owner's setting.
t_pickowner() {
  picksetup; tune '.models.allowed.claude += ["m2"]'
  loop control card 7 builder m2 high >/dev/null || fail "control card did not take #7's builder"
  fx_in 'SEATCARD=7; PICK=""; modelpick c1-7 7; printf "%s\n" "$PICK"; seat builder | jq -c "{model, effort}"'
  [ "$(cat "$T/$CASE/run.out")" = $'{"group":"small docs","choice":{"model":"m2","effort":"high"},"by":"owner","trial":false,"mode":"shadow"}\n{"model":"m2","effort":"high"}' ] \
    || fail "the pick of a card the owner set the builder of is not by owner on m2 high, or the card's builder moved: $(cat "$T/$CASE/run.out")"
}

# Bug caught: a card that starts again for the same issue was picked again, so a restart could move it to another
# group or choice. The issue's earlier card (blocked) holds a pick of another group and builder than this issue now
# gets; the new card keeps that pick, with the rule's setting as it is now.
t_pickrestart() {
  picksetup
  jq -cn '{card: "c0-7", issue: 7, step: "blocked", time: "2026-11-01T00:00:00Z", tokens: {claude: 0, codex: 0}, result: "blocked", sha: "", reason: "tests failed",
    pick: {group: "large code", choice: {model: "m0", effort: "low"}, by: "auto", trial: false, mode: "on"}}' >> "$ST/cards.jsonl"
  fx_in 'SEATCARD=7; PICK=""; modelpick c1-7 7; printf "%s %s\n" "$PICKCARD" "$PICK"'
  [ "$(cat "$T/$CASE/run.out")" = 'c1-7 {"group":"large code","choice":{"model":"m0","effort":"low"},"by":"auto","trial":false,"mode":"shadow"}' ] \
    || fail "the restarted card did not keep its issue's pick: $(cat "$T/$CASE/run.out")"
}

# Bug caught: a line the loop writes for a card outside card(), which holds no pick of its own, lost the card's pick:
# the stopped line of a card that `control stop` ended (stopped()), and the blocked line of one whose process was gone
# (block(), as revive() and endcard() call it). Each is called as the loop calls it, with no PICK set.
t_pickafter() {
  picksetup
  p='{"group":"small docs","choice":{"model":"m","effort":"medium"},"by":"auto","trial":false,"mode":"shadow"}'
  for l in '{"step":"worktree","result":"ok"}' '{"step":"start","result":"","of":"build"}'; do
    jq -c --argjson p "$p" '{card: "c1-7", issue: 7, time: "2026-11-01T00:00:00Z", tokens: {claude: 0, codex: 0}, sha: "", reason: ""} + . + {pick: $p}' <<<"$l" >> "$ST/cards.jsonl"
  done
  # The build's output: stopped() writes a line only for a session that wrote some.
  fx_in 'mkdir -p "$CARDS" && echo "{}" > "$CARDS/c1-7.out" && stopped c1-7 7 && block c1-7 7 "$CARDS/c1-7" "its process was gone"'
  [ "$(jq -sc --argjson p "$p" 'map(select(.step | IN("build", "blocked")) | [.step, .result, .pick == $p])' "$ST/cards.jsonl")" = '[["build","stopped",true],["blocked","blocked",true]]' ] \
    || fail "the stopped and blocked lines written outside card() do not carry the card's pick: $(st '[.step, .result, .pick] | tostring' | tr '\n' ' '); $(cat "$T/$CASE/run.out")"
}

# Bugs caught: the table of picked cards left out a blocked attempt's spend, so a group that blocks looked cheap, also
# when that attempt ran with the rule off and has no pick; it gave a part sum for a group with an unpriced step; or it
# counted a card that `retry` (or `control stop`) moved out as still open. Group small docs: issue 7 blocked after a $2
# build with no pick, then landed on a second card, picked ($2 build, $1 review): $5 for 1 landed card, none on the
# first try. Group small code: issue 8 landed with a build whose usage was not read (no price), issue 9 is on the
# belt, and issue 10 blocked and was retried (its lines in the retried file), so it is not open.
t_picktable() {
  export TZ=UTC; setup '[]'; S=$ST; d=$(date -u +%F) m=0
  seatset model claude-sonnet-5-5; seatset reviewer gpt-6.1-sol
  B='{"tokens":{"claude":1000000,"codex":0},"usage":{"input":1000000,"write":0,"write1h":0,"read":0,"output":0},"model":"claude-sonnet-5-5"}'
  V='{"tokens":{"claude":0,"codex":500000},"usage":{"input":500000,"read":0,"output":0},"visible":"no","model":"gpt-6.1-sol"}'
  T0='{"sec":60,"usage":{"input":0,"write":0,"write1h":0,"read":0,"output":0}}'
  # One line a minute after the one before, to the card records, or to PF; a picked line (the pick comes later) when
  # <group> is empty, a line with no pick when it is "-". Each card opens with its picked line, as a card does: a
  # card's steps are its lines after the first.
  pline() { # <card> <issue> <group> <step> [<result> [<extra json>]]
    jq -cn --arg c "$1" --argjson i "$2" --arg g "$3" --arg s "$4" --arg r "${5:-ok}" --argjson x "${6:-{\}}" --arg t "$(printf '%sT00:%02d:00Z' "$d" "$m")" \
      '{card: $c, issue: $i, step: $s, time: $t, tokens: {claude: 0, codex: 0}, result: $r, sha: "", reason: ""}
        + if $g == "" then {title: "T"} elif $g == "-" then {} else {pick: {group: $g, choice: {model: "claude-sonnet-5-5", effort: "medium"}, by: "auto", trial: false, mode: "shadow"}} end * $x' >> "${PF:-$S/cards.jsonl}"
    m=$((m + 1))
  }
  pline c1-7 7 '' picked; pline c1-7 7 - build ok "$B"; pline c1-7 7 - blocked blocked '{"reason":"review 1: no answer"}'
  pline c2-7 7 '' picked; pline c2-7 7 'small docs' build ok "$B"; pline c2-7 7 'small docs' review GO "$V"; pline c2-7 7 'small docs' test pass "$T0"
  pline c2-7 7 'small docs' landed ok '{"sha":"abc","product":false}'
  pline c1-8 8 '' picked; pline c1-8 8 'small code' build ok '{"model":"claude-sonnet-5-5"}'; pline c1-8 8 'small code' review GO "$V"; pline c1-8 8 'small code' test pass "$T0"
  pline c1-8 8 'small code' landed ok '{"sha":"abd","product":false}'
  pline c1-9 9 '' picked; pline c1-9 9 'small code' build ok "$B"
  PF=$S/retried.jsonl; pline c1-10 10 '' picked; pline c1-10 10 'small code' build ok "$B"; pline c1-10 10 'small code' blocked blocked '{"reason":"tests failed"}'; unset PF
  [ "$(loop snapshot | jq -c '.cost.picks')" = '[{"group":"small code","model":"claude-sonnet-5-5","effort":"medium","cards":3,"landed":1,"usd":null,"firstTry":1,"reviews":1,"open":1},{"group":"small docs","model":"claude-sonnet-5-5","effort":"medium","cards":1,"landed":1,"usd":5,"firstTry":0,"reviews":1,"open":0}]' ] \
    || fail "the snapshot's picks by group and builder: $(loop snapshot | jq -c '.cost.picks')"
}
