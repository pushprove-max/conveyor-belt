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
  # The judge's pick of the seats (asked) is checked by the cases of cardseats.test.sh.
  [ "$(jq -sc --argjson w "$want" '(map(.step) | index("worktree")) as $i | [.[$i:][] | select(.step | IN("push", "pushed", "issue") | not) | .pick | del(.asked) == $w] | unique' "$ST/cards.jsonl")" = '[true]' ] \
    || fail "a line of the card from its worktree on does not carry its pick $want: $(st '[.step, .pick] | tostring' | tr '\n' ' ')"
  [ "$(st 'select(.step == "build") | "\(.model) \(.effort)"')" = 'm medium' ] || fail "the card did not build on the project's builder: $(st 'select(.step == "build")')"
  recok "$ST/cards.jsonl" "a picked card"
}

# Bug caught: the group did not follow the issue: an issue that names a pipeline file (the pack's pipelineFiles, a
# file under conveyor/lib/ here) was put with code, one at the split thresholds (three Done-when items,
# split.doneWhen 3) with small ones, or one with the label documentation with code. One fixture, one call an issue.
# Issue 11 names only the directory conveyor/lib/, in Markdown bold: a path with no extension that SPLITSIZE's files
# do not hold, and a "**" that onpipeline() kept as part of the name; it went into the code group (#825).
# Also caught (#766): an issue at the thresholds but under twice them (issue 9) was not medium, or one at twice them
# (issue 12, six Done-when items) was not large.
t_pickgroups() {
  setup "[$(issue 8 2026-01-01 | jq -c '.body = "Change conveyor/lib/run.sh."'),$(issue 9 2026-01-01 | jq -c '.body = "Change src/a.js.\n\nDone when:\n- one\n- two\n- three"'),$(issue 10 2026-01-01 documentation | jq -c '.body = "Change src/a.js."'),$(issue 11 2026-01-01 | jq -c '.body = "Change how the scripts in **conveyor/lib/** log."'),$(issue 12 2026-01-01 | jq -c '.body = "Change src/a.js.\n\nDone when:\n- one\n- two\n- three\n- four\n- five\n- six"')]"
  tune '.split.doneWhen = 3 | .pipelineFiles = ["conveyor/lib/"]'
  loop control rules pick=on >/dev/null || fail "control rules pick=on was refused"
  fx_in 'for n in 8 9 10 11 12; do SEATCARD=$n PICK=""; modelpick c1-$n $n 2>/dev/null; jq -r "\"\(.group) \(.mode)\"" <<<"$PICK"; done'
  [ "$(cat "$T/$CASE/run.out")" = $'small pipeline on\nmedium code on\nsmall docs on\nsmall pipeline on\nlarge code on' ] || fail "the groups of a pipeline, a medium, a documentation, a pipeline-directory and a large issue: $(cat "$T/$CASE/run.out")"
}

# Bug caught: a card whose builder the owner set was recorded as the rule's choice, or the pick moved its builder off
# the owner's setting.
t_pickowner() {
  picksetup; tune '.models.allowed.claude += ["m2"]'
  loop control card 7 builder m2 high >/dev/null || fail "control card did not take #7's builder"
  fx_in 'SEATCARD=7; PICK=""; modelpick c1-7 7 2>/dev/null; jq -c "del(.asked)" <<<"$PICK"; seat builder | jq -c "{model, effort}"'
  [ "$(cat "$T/$CASE/run.out")" = $'{"group":"small docs","choice":{"model":"m2","effort":"high"},"by":"owner","trial":false,"mode":"shadow"}\n{"model":"m2","effort":"high"}' ] \
    || fail "the pick of a card the owner set the builder of is not by owner on m2 high, or the card's builder moved: $(cat "$T/$CASE/run.out")"
  # Bug caught (R276): with m2 taken off the pack's allowed models, seat() passes the owner's builder over and the card
  # builds on the project's, but the pick still said by owner, as it read the record's setting alone; or, with the
  # project's builder (named with its CLI, so it stands) on the same m2 high, as it compared the setting to that seat.
  loop control model claude m2 high >/dev/null || fail "control model was refused"
  tune '.models.allowed.claude -= ["m2"]'
  fx_in 'SEATCARD=7; PICK=""; modelpick c1-7 7 2>/dev/null; jq -c "del(.asked)" <<<"$PICK"'
  [ "$(cat "$T/$CASE/run.out")" = '{"group":"small docs","choice":{"model":"m2","effort":"high"},"by":"auto","trial":false,"mode":"shadow"}' ] \
    || fail "the pick of a card whose owner's builder the pack no longer allows is not by auto on the project's m2 high: $(cat "$T/$CASE/run.out")"
}

# Bugs caught (#828): with pick=on an eligible card whose issue number is in the 1-in-5 share did not build on the
# challenger (claude-sonnet-5-5 medium) with trial: true, or its review moved off the project's reviewer; a trial card
# whose change touches a pipeline file its issue does not name was not flagged on its lines and in the snapshot. A
# whole card (see the top): only a card shows that the trial reaches the build session's seat, and the flag its lines.
# Issue 10 names docs/guide.md (small docs); the build changes a.txt, a pipeline file here.
t_picktrial() {
  setup "[$(issue 10 2026-01-01 | jq -c '.body = "Fix a typo in docs/guide.md."')]"; echo "$GO" > "$STUB/review.1"
  tune '.models.allowed.claude += ["claude-sonnet-5-5"] | .pipelineFiles = ["a.txt"]'
  loop control rules pick=on >/dev/null || fail "control rules pick=on was refused"
  loop run 1 >/dev/null
  [ "$(st 'select(.step == "build") | "\(.model) \(.effort) \(.pick.trial) \(.pick.choice | tojson)"')" = 'claude-sonnet-5-5 medium true {"model":"claude-sonnet-5-5","effort":"medium"}' ] \
    || fail "the trial card did not build on the challenger: $(st 'select(.step == "build")')"
  [ "$(st 'select(.step == "review") | "\(.model) \(.pick.pipeline | tojson)"')" = 'x ["a.txt"]' ] \
    || fail "the trial card's review left the project's reviewer, or its pick does not flag a.txt: $(st 'select(.step == "review")')"
  [ "$(loop snapshot | jq -c '.cost.trials.flagged | map([.issue, .group, .files])')" = '[[10,"small docs",["a.txt"]]]' ] \
    || fail "the snapshot does not flag the trial card: $(loop snapshot | jq -c .cost.trials)"
  recok "$ST/cards.jsonl" "a trial card"
}

# Bugs caught (#828): a second eligible card in the share took the trial while one was in flight; a card out of the
# share, a pipeline one or a medium one took it; a blocked trial card's retry built on the challenger again; two
# blocked trial cards of a group did not drop its challenger (the next card of the group in the share), the drop
# reached another group, or the snapshot did not list it. One fixture; each card is picked as card() picks it (pk),
# after its picked line, and prints its group, trial, the pick's builder and the builder seat() gives it. Issues 15,
# 35 and 40 are small code, 20, 11, 45 and 55 small docs, 25 pipeline and 30 medium code (#766: a medium group the
# owner did not add gets the defaults).
# Also caught: c1-15's filed line (its follow-ups, filed before it lands) freed the trial for c1-20; once c1-35's
# issue was closed while it was blocked (shut()), the snapshot no longer listed the drop the rule still applies; a
# builder the owner set for #45 during its trial was replaced by the challenger; c1-45, its process gone before any
# review and blocked by `shut 45` (which did not load trialflag()) on a change to b.txt, a pipeline file the fixture
# tracks (it leaves conveyor/ out), was not flagged; c1-55 took the trial while the challenger's account
# was at the weekly limit guard.
t_picktrialrules() {
  local code docs
  code=$(for n in 15 35 40; do issue $n 2026-01-01 | jq -c '.body = "Change src/a.js."'; done | paste -sd, -)
  docs=$(for n in 20 11 45 55; do issue $n 2026-01-01 | jq -c '.body = "Fix a typo in docs/guide.md."'; done | paste -sd, -)
  setup "[$code,$docs,$(issue 25 2026-01-01 | jq -c '.body = "Change conveyor/lib/run.sh."'),$(issue 30 2026-01-01 | jq -c '.body = "Change src/a.js.\n\nDone when:\n- one\n- two\n- three"')]"
  tune '.split.doneWhen = 3 | .pipelineFiles = ["conveyor/lib/", "b.txt"] | .models.allowed.claude += ["claude-sonnet-5-5", "m2"]'
  loop control rules pick=on >/dev/null || fail "control rules pick=on was refused"
  cat > "$T/$CASE/pk.sh" <<'EOF'
m=0
tl() { # <card> <issue> <step> [<pick>] [<more fields>]: a line of the card, a minute after the one before
  jq -cn --arg c "$1" --argjson n "$2" --arg s "$3" --argjson p "${4:-null}" --argjson x "${5:-null}" --arg t "$(printf '2026-11-01T00:%02d:00Z' "$m")" \
    '{card: $c, issue: $n, step: $s, time: $t, tokens: {claude: 0, codex: 0}, result: (if $s == "blocked" then "blocked" else "ok" end), sha: "", reason: ""}
      + if $s == "picked" then {title: "T"} else {pick: $p} end + ($x // {})' >> "$STATE"
  m=$((m + 1))
}
pk() { # <card> <issue> [<step>]: picked as card() picks it; then a line of that step with its pick
  tl "$1" "$2" picked; SEATCARD=$2 PICK='' PICKSEAT=''
  modelpick "$1" "$2" 2>/dev/null
  echo "$1 $(jq -r '"\(.group) \(.trial) \(.choice.model)"' <<<"$PICK") $(seat builder | jq -r .model)"
  [ -z "${3:-}" ] || tl "$1" "$2" "$3" "$PICK"
}
held() { jq -c --arg c "$1" 'select(.card == $c and .step == "worktree") | .pick' "$STATE"; } # <card>: its pick
pk c1-15 15 worktree; tl c1-15 15 filed "$(held c1-15)"; pk c1-20 20; pk c1-11 11; pk c1-25 25; pk c1-30 30
tl c1-15 15 blocked "$(held c1-15)"; pk c2-15 15
pk c1-35 35 worktree; tl c1-35 35 blocked "$(held c1-35)"; shut '[35]' >/dev/null
pk c1-40 40; pk c1-45 45
loop control card 45 builder m2 high >/dev/null; echo "owner $(SEATCARD=45 seat builder | jq -r .model)"
git -C "$R" worktree add -q --detach "$CARDS/c1-45" && echo x > "$CARDS/c1-45/b.txt"
# Its process gone before any review: `shut 45` blocks it (shutopen(), lib/run.sh), run as its own command, so the
# block has only the files that command loads, not card()'s.
sh -c : & d=$!; wait "$d"; tl c1-45 45 worktree "$PICK" "{\"pid\": $d, \"started\": \"x\"}"
loop shut 45 >/dev/null 2>&1
jq -cn '{time: (now | todate), pct: 95}' >> "${STATE%/*}/limit.jsonl"; loop control guard 90 >/dev/null; pk c1-55 55
EOF
  fx_in ". '$T/$CASE/pk.sh'"
  [ "$(cat "$T/$CASE/run.out")" = 'c1-15 small code true claude-sonnet-5-5 claude-sonnet-5-5
c1-20 small docs false m m
c1-11 small docs false m m
c1-25 small pipeline false m m
c1-30 medium code false m m
c2-15 small code false m m
c1-35 small code true claude-sonnet-5-5 claude-sonnet-5-5
c1-40 small code false m m
c1-45 small docs true claude-sonnet-5-5 claude-sonnet-5-5
owner m2
c1-55 small docs false m m' ] || fail "the trials of the cards picked: $(cat "$T/$CASE/run.out")"
  [ "$(st 'select(.card == "c1-45" and .step == "blocked") | .pick.pipeline | tojson')" = '["b.txt"]' ] \
    || fail "the trial card blocked before its review does not flag its pipeline file: $(st 'select(.card == "c1-45")')"
  [ "$(loop snapshot | jq -c '.cost.trials.flagged | map(.card)')" = '["c1-45"]' ] \
    || fail "the snapshot does not flag the trial card blocked before its review: $(loop snapshot | jq -c .cost.trials)"
  [ "$(loop snapshot | jq -c '.cost.trials.dropped')" = '[{"group":"small code","model":"claude-sonnet-5-5","effort":"medium","cards":["c1-15","c1-35"]}]' ] \
    || fail "the snapshot does not list the dropped challenger of small code: $(loop snapshot | jq -c .cost.trials)"
}

# A line of a card of group small code (tln, as card() writes it), with the trial pick for its trial lines.
tln() { # <card> <issue> <step>
  jq -cn --arg c "$1" --argjson n "$2" --arg s "$3" '{card: $c, issue: $n, step: $s, time: "2026-11-01T00:00:00Z",
    tokens: {claude: 0, codex: 0}, result: (if $s == "blocked" then "blocked" else "ok" end), sha: "", reason: ""}
    + (if $s == "picked" then {title: "T"} else {pick: {group: "small code", choice: {model: "claude-sonnet-5-5", effort: "medium"}, by: "auto", trial: true, mode: "on"}} end)' >> "$ST/cards.jsonl"
}
# Issues 15 and 20, small code, in the share (issue number a multiple of 5), with the rule On.
trialsetup() {
  setup "[$(for n in 15 20; do issue $n 2026-01-01 | jq -c '.body = "Change src/a.js."'; done | paste -sd, -)]"
  tune '.models.allowed.claude += ["claude-sonnet-5-5"]'
  loop control rules pick=on >/dev/null || fail "control rules pick=on was refused"
}
# Bug caught (R99): the claim of a trial card that never reached its worktree line (the loop restarted after
# picktrial() wrote trial.card) held the trial for good, as nothing ends a card with only a picked line. c1-10 holds
# the claim, its process gone; c1-15 takes the trial, and its own claim, with only its picked line, still holds the
# trial from c1-20 while its process runs.
t_picktrialstale() {
  trialsetup
  tln c1-10 10 picked
  local d; sh -c : & d=$!; wait "$d"; printf 'c1-10\n%s\nx\n' "$d" > "$ST/trial.card"
  fx_in 'for k in 15 20; do tln c1-$k $k picked; SEATCARD=$k PICK="" PICKSEAT=""; modelpick c1-$k $k 2>/dev/null; echo "c1-$k $(jq -c .trial <<<"$PICK")"; done'
  [ "$(cat "$T/$CASE/run.out")" = $'c1-15 true\nc1-20 false' ] \
    || fail "trial.card naming c1-10 (only a picked line, its process gone), then c1-15 claiming: the trials of c1-15 and c1-20: $(cat "$T/$CASE/run.out")"
}
# Bug caught (R100): the group's second trial block, written after picktrial() counted the blocks and before it took
# the claim, let one more trial card run on a dropped challenger: the claim's card had ended, so the claim was free,
# and the count was not read again. c1-5 is blocked; c1-10, the claim's card, blocks inside challenger(), which runs
# between the two.
t_picktrialrace() {
  trialsetup
  tln c1-5 5 blocked; tln c1-10 10 worktree; printf 'c1-10\n' > "$ST/trial.card"
  fx_in 'eval "real$(declare -f challenger)"; challenger() { tln c1-10 10 blocked; realchallenger "$@"; }
    tln c1-15 15 picked; SEATCARD=15 PICK="" PICKSEAT=""; modelpick c1-15 15 2>"$T/$CASE/pick.err"; grep "no trial" "$T/$CASE/pick.err"; echo "trial $(jq -c .trial <<<"$PICK")"'
  [ "$(cat "$T/$CASE/run.out")" = $'conveyor: card c1-15: no trial: two trial cards of the group were blocked: its challenger is dropped\ntrial false' ] \
    || fail "c1-10 (the claim's trial card) blocked between the count and the claim, c1-5 blocked before: c1-15's pick: $(cat "$T/$CASE/run.out")"
}
# Bug caught (R277): picktrial() counted the blocked line of a card that pushed after it (a landed card whose process
# died is blocked, then pushes), so c1-5's block and c1-10's made two and dropped the challenger, while the snapshot's
# trials.dropped, which does not count c1-10, listed no drop. Both see one block: c1-15 is a trial, and no drop is listed.
t_picktrialpushed() {
  trialsetup
  tln c1-5 5 picked; tln c1-5 5 worktree; tln c1-5 5 blocked
  for s in picked worktree landed blocked pushed; do tln c1-10 10 "$s"; done
  fx_in 'tln c1-15 15 picked; SEATCARD=15 PICK="" PICKSEAT=""; modelpick c1-15 15 2>/dev/null; echo "trial $(jq -c .trial <<<"$PICK")"'
  [ "$(cat "$T/$CASE/run.out")" = 'trial true' ] && [ "$(loop snapshot | jq -c '.cost.trials.dropped')" = '[]' ] \
    || fail "c1-5 blocked and c1-10 landed, blocked, pushed: c1-15's pick ($(cat "$T/$CASE/run.out")) and the snapshot's dropped ($(loop snapshot | jq -c .cost.trials.dropped)) are not a trial and none"
}

# Bug caught: a card that starts again for the same issue was picked again, so a restart could move it to another
# group. The issue's earlier card (blocked) holds a pick of another group and builder than this issue now gets; the
# new card keeps that pick, with the rule's setting as it is now. Bug: in Shadow it also kept the earlier builder (m0
# at low, the On pick's) as its choice, while it builds on the project's m at medium.
t_pickrestart() {
  picksetup
  jq -cn '{card: "c0-7", issue: 7, step: "blocked", time: "2026-11-01T00:00:00Z", tokens: {claude: 0, codex: 0}, result: "blocked", sha: "", reason: "tests failed",
    pick: {group: "large code", choice: {model: "m0", effort: "low"}, by: "auto", trial: false, mode: "on"}}' >> "$ST/cards.jsonl"
  fx_in 'SEATCARD=7; PICK=""; modelpick c1-7 7 2>/dev/null; printf "%s %s\n" "$PICKCARD" "$(jq -c "del(.asked)" <<<"$PICK")"'
  [ "$(cat "$T/$CASE/run.out")" = 'c1-7 {"group":"large code","choice":{"model":"m","effort":"medium"},"by":"auto","trial":false,"mode":"shadow"}' ] \
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
  [ "$(loop snapshot | jq -c '.cost.picks')" = '[{"group":"small code","model":"claude-sonnet-5-5","effort":"medium","cards":3,"landed":1,"usd":null,"estimate":0,"firstTry":1,"reviews":1,"open":1},{"group":"small docs","model":"claude-sonnet-5-5","effort":"medium","cards":1,"landed":1,"usd":5,"estimate":0,"firstTry":0,"reviews":1,"open":0}]' ] \
    || fail "the snapshot's picks by group and builder: $(loop snapshot | jq -c '.cost.picks')"
}

# The snapshot gives the Board each card's seats (its pick's asked, from its last line with a pick) on the belt, in
# Needs you and in Landed today, and the pack's pick lists with each program's efforts (packPick) for the Rules tab's
# Pick settings row. Bug caught (#1047, #1067): a card's page could not show the Judge's seats, their reasons or a
# clamp, as the snapshot dropped them, or the row could not show the lists the pack holds, nor each model's own efforts.
t_pickseatsnap() {
  export TZ=UTC; setup '[]'
  tune '.pick = {builder: {"claude-opus-5-5": {min: "medium", max: "high"}}}'
  local d m=0 A
  A='{"builder":{"model":"claude-sonnet-5-5","effort":"medium","why":"small","asked":{"model":"claude-sonnet-5-5","effort":"low"},"clamp":"low is out of range: claude-sonnet-5-5 at medium"},
    "reviewer":{"model":"gpt-6.1-sol","effort":"medium","why":"r","asked":{"model":"gpt-6.1-sol","effort":"medium"}},
    "judge":{"model":"claude-opus-5-5","effort":"medium","why":"j","asked":{"model":"claude-opus-5-5","effort":"medium"}},"model":"claude-opus-5-5"}'
  d=$(date -u +%F)
  sl() { # <card> <issue> <step> <result> [<extra json> [<asked json>]]
    jq -cn --arg c "$1" --argjson i "$2" --arg s "$3" --arg r "$4" --argjson x "${5:-{\}}" --argjson a "${6:-$A}" --arg t "$(printf '%sT00:%02d:00Z' "$d" "$m")" \
      '{card: $c, issue: $i, step: $s, time: $t, tokens: {claude: 0, codex: 0}, result: $r, sha: "", reason: ""}
        + if $s == "picked" then {title: "T"} else {pick: {group: "small code", choice: {model: "m", effort: "medium"}, by: "auto", trial: false, mode: "on", asked: $a}} end * $x' >> "$ST/cards.jsonl"
    m=$((m + 1))
  }
  sl c1-7 7 picked ok; sl c1-7 7 build ok; sl c1-7 7 landed ok '{"sha":"abc","product":false}'
  sl c1-8 8 picked ok; sl c1-8 8 build ok; sl c1-8 8 blocked blocked '{"reason":"tests failed"}'
  sl c1-9 9 picked ok; sl c1-9 9 build ok '{}' '{"failed":"the judge timed out"}'
  # A trial at the Judge's effort, a promoted card with a reviewer the owner promoted, a card picked before the pick
  # said judged (#1133: its choice is the Judge's builder, which it builds on), and a card on the Judge's builder.
  sl c1-10 10 picked ok; sl c1-10 10 build ok '{"pick":{"trial":true,"choice":{"model":"claude-sonnet-5-5","effort":"medium"},"trialEffort":"high"}}'
  sl c1-11 11 picked ok; sl c1-11 11 build ok '{"pick":{"promoted":true,"choice":{"model":"claude-sonnet-5-5","effort":"low"},"seats":{"reviewer":{"model":"gpt-6.2-sol","effort":"high"}}}}'
  sl c1-12 12 picked ok; sl c1-12 12 build ok '{"pick":{"choice":{"model":"claude-sonnet-5-5","effort":"medium"}}}'
  sl c1-13 13 picked ok; sl c1-13 13 build ok '{"pick":{"choice":{"model":"claude-sonnet-5-5","effort":"medium"},"judged":true}}'
  local s; s=$(loop snapshot) || fail "the snapshot failed"
  [ "$(jq -c '[.landed[] | select(.issue == 7) | .seats.builder.clamp]' <<<"$s")" = '["low is out of range: claude-sonnet-5-5 at medium"]' ] \
    || fail "Landed today has no seats: $(jq -c '.landed' <<<"$s" | head -c 600)"
  [ "$(jq -c '[.needsYou.blocked[] | select(.issue == 8) | .seats.builder.why]' <<<"$s")" = '["small"]' ] \
    || fail "Needs you has no seats: $(jq -c '.needsYou.blocked' <<<"$s" | head -c 600)"
  # The seats each card runs on go with the Judge's pick (run, #1086). Bug caught: the Board showed the Judge's seats on
  # a trial (it builds on the challenger at trialEffort, and is reviewed on the project's), on a promoted card (the
  # challenger, and the reviewer the owner promoted), on a card the rule kept on the project's builder (c1-7: its
  # choice is not the Judge's builder) and on a failed pick. Bug caught (#1133): a card picked before the pick said
  # judged (c1-12) builds on the Judge's builder, its choice, but showed the project's and "does not run on it".
  [ "$(jq -c '[.belt[] | select(.issue == 9) | .seats]' <<<"$s")" = '[{"failed":"the judge timed out","mode":"on","run":{"builder":null,"reviewer":null,"judge":null}}]' ] \
    || fail "a card on the belt has no seats: $(jq -c '.belt' <<<"$s" | head -c 600)"
  local j='{"model":"claude-opus-5-5","effort":"medium","by":"judge"}' r='{"model":"gpt-6.1-sol","effort":"medium","by":"judge"}'
  [ "$(jq -c '[.landed[] | select(.issue == 7) | .seats.run.builder]' <<<"$s")" = '[null]' ] || fail "a card kept on the project's builder: $(jq -c '.landed' <<<"$s" | head -c 600)"
  [ "$(jq -c '[.belt[] | select(.issue == 10) | .seats.run]' <<<"$s")" = '[{"builder":{"model":"claude-sonnet-5-5","effort":"high","by":"trial"},"reviewer":null,"judge":null}]' ] \
    || fail "a trial's seats: $(jq -c '[.belt[] | select(.issue == 10) | .seats]' <<<"$s")"
  [ "$(jq -c '[.belt[] | select(.issue == 11) | .seats.run]' <<<"$s")" = '[{"builder":{"model":"claude-sonnet-5-5","effort":"low","by":"promoted"},"reviewer":{"model":"gpt-6.2-sol","effort":"high","by":"promoted"},"judge":'"$j"'}]' ] \
    || fail "a promoted card's seats: $(jq -c '[.belt[] | select(.issue == 11) | .seats]' <<<"$s")"
  [ "$(jq -c '[.belt[] | select(.issue == 12) | .seats.run]' <<<"$s")" = '[{"builder":{"model":"claude-sonnet-5-5","effort":"medium","by":"judge"},"reviewer":'"$r"',"judge":'"$j"'}]' ] \
    || fail "a card picked before the pick said judged, on the Judge's builder: $(jq -c '[.belt[] | select(.issue == 12) | .seats]' <<<"$s")"
  [ "$(jq -c '[.belt[] | select(.issue == 13) | .seats.run]' <<<"$s")" = '[{"builder":{"model":"claude-sonnet-5-5","effort":"medium","by":"judge"},"reviewer":'"$r"',"judge":'"$j"'}]' ] \
    || fail "a card on the Judge's seats: $(jq -c '[.belt[] | select(.issue == 13) | .seats]' <<<"$s")"
  [ "$(jq -c '[.packPick.lists, .packPick.efforts.claude, .packPick.efforts.codex]' <<<"$s")" = '[{"builder":{"claude-opus-5-5":{"min":"medium","max":"high"}}},["low","medium","high","xhigh","max"],["minimal","low","medium","high","xhigh"]]' ] \
    || fail "the snapshot's packPick: $(jq -c .packPick <<<"$s")"
}

# The cards of #829's cases, all of group small docs, by auto, with the rule On: one line a minute after the one
# before, from 2026-11-01. pcard writes a card's picked line, its build (1M input tokens on <model>) and its end.
PLM=0
pl() { # <card> <issue> <step> <trial | default | promoted> [<result> [<extra json>]]
  jq -cn --arg c "$1" --argjson i "$2" --arg s "$3" --arg p "$4" --arg r "${5:-ok}" --argjson x "${6:-{\}}" \
    --arg t "$(printf '2026-11-01T%02d:%02d:00Z' $((PLM / 60)) $((PLM % 60)))" \
    '{card: $c, issue: $i, step: $s, time: $t, tokens: {claude: 0, codex: 0}, result: $r, sha: "", reason: ""}
      + if $s == "picked" then {title: "T"} else {pick: ({group: "small docs", by: "auto", mode: "on"}
        + {trial: {trial: true, choice: {model: "claude-sonnet-5-5", effort: "medium"}}, default: {trial: false, choice: {model: "m", effort: "medium"}},
           promoted: {trial: false, promoted: true, choice: {model: "claude-sonnet-5-5", effort: "medium"}},
           builder: {trial: false, choice: {model: "claude-sonnet-5-5", effort: "medium"}}}[$p])} end * $x' >> "$ST/cards.jsonl"
  PLM=$((PLM + 1))
}
pcard() { # <card> <issue> <trial | default | promoted> <build model> <landed | blocked>
  pl "$1" "$2" picked "$3"
  pl "$1" "$2" build "$3" ok "{\"tokens\":{\"claude\":1000000,\"codex\":0},\"usage\":{\"input\":1000000,\"write\":0,\"write1h\":0,\"read\":0,\"output\":0},\"model\":\"$4\"}"
  if [ "$5" = landed ]; then pl "$1" "$2" landed "$3" ok "{\"sha\":\"s$2\",\"product\":false}"; else pl "$1" "$2" blocked "$3" blocked '{"reason":"tests failed"}'; fi
}

# Bugs caught (#829): Needs you asked for the owner's decision before ten trial cards of a group had ended, or not at
# the tenth, or without both sides' counts and spend per landed card; it asked again for the same ten after the owner
# chose keep; the rule promoted the challenger by itself once the decision was due (an eligible card out of the share
# built on it); `control pick` took a group that cannot have trials (large code); after keep, the two trial cards
# blocked before it still dropped the challenger, so the next card in the share (issue 25) built on the default and
# the snapshot still listed the group as dropped. Trial cards: 8 land and 2 block, each a $2 build
# (claude-sonnet-5-5); default cards: 2 land, each a $4 build (claude-opus-5-5).
t_pickdecide() {
  setup "[$(for n in 21 25; do issue $n 2026-01-01 | jq -c '.body = "Fix a typo in docs/guide.md."'; done | paste -sd, -)]"
  tune '.models.allowed.claude += ["claude-sonnet-5-5"]'
  loop control rules pick=on >/dev/null || fail "control rules pick=on was refused"
  for n in 101 102 103 104 105 106 107 108; do pcard "c1-$n" "$n" trial claude-sonnet-5-5 landed; done
  pcard c1-109 109 trial claude-sonnet-5-5 blocked
  pcard c1-201 201 default claude-opus-5-5 landed; pcard c1-202 202 default claude-opus-5-5 landed
  [ "$(loop snapshot --fresh | jq -c '.needsYou.pick')" = '[]' ] || fail "Needs you asks for a decision after nine trial cards: $(loop snapshot | jq -c .needsYou.pick)"
  pcard c1-110 110 trial claude-sonnet-5-5 blocked
  [ "$(loop snapshot --fresh | jq -c '.needsYou.pick | map(del(.reason))')" = '[{"group":"small docs","title":"Pick settings: decide on claude-sonnet-5-5 at medium effort for small docs cards","since":"2026-11-01T00:35:00Z","time":"2026-11-01T00:35:00Z","trial":{"cards":10,"landed":8,"ended":10,"usd":20,"perLanded":2.5},"default":{"cards":2,"landed":2,"ended":2,"usd":8,"perLanded":4}}]' ] \
    || fail "the decision after ten trial cards: $(loop snapshot | jq -c .needsYou.pick)"
  [ "$(loop snapshot | jq -r '.needsYou.pick[0].reason')" = 'Trial cards on claude-sonnet-5-5: 10, 8 landed, $2.50 for each landed card. Default cards: 2, 2 landed, $4.00 for each landed card. Conveyor does not promote by itself. Choose promote, keep or drop: conveyor.sh control pick small docs promote, keep or drop.' ] \
    || fail "the decision's line: $(loop snapshot | jq -r '.needsYou.pick[0].reason')"
  fx_in 'SEATCARD=21; PICK=""; PICKSEAT=""; modelpick c1-21 21 2>/dev/null; jq -c "[.trial, .choice.model]" <<<"$PICK"; seat builder | jq -r .model'
  [ "$(cat "$T/$CASE/run.out")" = $'[false,"m"]\nm' ] || fail "the rule promoted the challenger by itself: $(cat "$T/$CASE/run.out")"
  loop control pick large code promote >/dev/null 2>&1 && fail "control pick took the group large code"
  loop control pick small docs keep >/dev/null || fail "control pick small docs keep was refused"
  [ "$(loop snapshot --fresh | jq -c '[.needsYou.pick, (.cost.trials.groups | map(.decision)), .cost.trials.dropped]')" = '[[],["keep"],[]]' ] \
    || fail "Needs you asks again about the ten trial cards the owner kept, or lists the group as dropped: $(loop snapshot | jq -c '[.needsYou.pick, .cost.trials]')"
  fx_in 'SEATCARD=25; PICK=""; PICKSEAT=""; modelpick c1-25 25 2>/dev/null; jq -c "[.trial, .choice.model]" <<<"$PICK"'
  [ "$(cat "$T/$CASE/run.out")" = '[true,"claude-sonnet-5-5"]' ] || fail "after keep, the card in the share is no trial: $(cat "$T/$CASE/run.out")"
}

# Bugs caught (#829): a promoted group's card did not build on the challenger, or did with trial true or with no
# promoted mark (the snapshot's cost check counts only marked cards); the 1 card in
# 5 of the group (an issue number that is a multiple of 5) did not stay on the project's builder; a group the owner
# dropped still had a trial card in the share; a promoted card started again after the owner took the promote back
# (keep) still recorded the challenger as its choice. Issues 21 and 25 are small docs, 15 small code.
t_pickpromote() {
  setup "[$(for n in 21 25; do issue $n 2026-01-01 | jq -c '.body = "Fix a typo in docs/guide.md."'; done | paste -sd, -),$(issue 15 2026-01-01 | jq -c '.body = "Change src/a.js."')]"
  tune '.models.allowed.claude += ["claude-sonnet-5-5"]'
  loop control rules pick=on >/dev/null && loop control pick small docs promote >/dev/null && loop control pick small code drop >/dev/null \
    || fail "control rules pick=on or control pick was refused"
  fx_in 'pk() { SEATCARD=$2 PICK="" PICKSEAT=""; modelpick "$1" "$2" 2>/dev/null; echo "$1 $(jq -r "\"\(.group) \(.trial) \(.promoted == true) \(.choice.model)\"" <<<"$PICK") $(seat builder | jq -r .model)"; }
    pk c1-21 21; pk c1-25 25; pk c1-15 15
    jq -cn "{card: \"c1-21\", issue: 21, step: \"blocked\", time: \"2026-11-01T00:00:00Z\", tokens: {claude: 0, codex: 0}, result: \"blocked\", sha: \"\", reason: \"tests failed\"}
      + {pick: {group: \"small docs\", choice: {model: \"claude-sonnet-5-5\", effort: \"medium\"}, by: \"auto\", trial: false, promoted: true, mode: \"on\"}}" >> "$STATE"
    loop control pick small docs keep >/dev/null; pk c2-21 21'
  [ "$(cat "$T/$CASE/run.out")" = 'c1-21 small docs false true claude-sonnet-5-5 claude-sonnet-5-5
c1-25 small docs false false m m
c1-15 small code false false m m
c2-21 small docs false false m m' ] || fail "the cards of a promoted and a dropped group: $(cat "$T/$CASE/run.out")"
}

# Bugs caught (#829): with the rule On, promoted cards that cost more per landed card than the group's default cards
# did not set the rule to shadow, did with no Needs you line, or left the card being picked on the challenger; the
# owner's `control rules pick=on` did not clear the line; a kept snapshot built before the owner promoted the group
# again (a new decision) set the rule back on that old count; a group promoted before any trial card had no cost
# check; a default card on a project's builder that is the challenger counted as promoted; a trial card's retry on
# the default named the default's model as the challenger, and split the sides by it. One promoted card lands on a $4
# claude-opus-5-5 build; two default cards on $2 claude-sonnet-5-5 builds, one of them with the challenger as its
# choice (the project's builder); then a trial card blocks and its retry lands on the default. The promoted card is
# c3-201 so that the snapshot reads it after the retry (c2-101): the group's model then comes from the retried card,
# and a challenger taken from the retry's default pick shows as the model m.
t_pickback() {
  setup "[$(issue 21 2026-01-01 | jq -c '.body = "Fix a typo in docs/guide.md."')]"
  tune '.models.allowed.claude += ["claude-sonnet-5-5"]'
  loop control rules pick=on >/dev/null && loop control pick small docs promote >/dev/null || fail "control rules pick=on or control pick was refused"
  pcard c3-201 201 promoted claude-opus-5-5 landed; pcard c1-301 301 default claude-sonnet-5-5 landed; pcard c1-302 302 builder claude-sonnet-5-5 landed
  [ "$(loop snapshot --fresh | jq -c '.cost.trials.groups | map([.group, .model, .promoted.cards, .promoted.perLanded, .default.cards, .default.perLanded, .over])')" = '[["small docs","claude-sonnet-5-5",1,4,2,2,true]]' ] \
    || fail "the snapshot has no cost check of a group promoted before any trial: $(loop snapshot | jq -c .cost.trials.groups)"
  pcard c1-101 101 trial claude-sonnet-5-5 blocked; pcard c2-101 101 default claude-sonnet-5-5 landed
  [ "$(loop snapshot --fresh | jq -c '.cost.trials.groups | map([.group, .model, .trial.cards, .promoted.cards, .default.cards, .over])')" = '[["small docs","claude-sonnet-5-5",1,1,2,true]]' ] \
    || fail "the snapshot does not find the promoted cards cost more: $(loop snapshot | jq -c .cost.trials.groups)"
  fx_in 'SEATCARD=21; PICK=""; PICKSEAT=""; modelpick c1-21 21 2>/dev/null; jq -c "[.mode, .choice.model]" <<<"$PICK"; seat builder | jq -r .model'
  [ "$(cat "$T/$CASE/run.out")" = $'["shadow","m"]\nm' ] || fail "the card picked as the rule went back to shadow: $(cat "$T/$CASE/run.out")"
  [ "$(jq -r '.rules.pick' "$ST/control.json")" = shadow ] || fail "the rule is not back in shadow: $(jq -c '[.rules.pick, .pickBack]' "$ST/control.json")"
  [ "$(loop snapshot --fresh | jq -c '.needsYou.pick | map([.title, .reason])')" = '[["Pick settings went back to Shadow","Promoted cards of small docs on claude-sonnet-5-5 at medium effort cost $4.00 for each landed card, more than the $2.00 of its default cards. Conveyor set Pick settings to Shadow. Before you set it to On again, choose keep or drop for the group: conveyor.sh control pick small docs keep or drop."]]' ] \
    || fail "Needs you has no line for the return to shadow: $(loop snapshot | jq -c .needsYou.pick)"
  loop control rules pick=on >/dev/null && [ "$(jq -c .pickBack "$ST/control.json")" = null ] || fail "control rules pick=on did not clear the line: $(jq -c .pickBack "$ST/control.json")"
  # Bug caught (R79): the owner's keep, made after the card read its control record (CARDCTL) and before modelpick()
  # ran, did not stop the return to shadow that the kept snapshot of the promote asked for: pickback() did not check
  # the decision again on the record as it is now.
  [ "$(loop snapshot --fresh | jq -c '.cost.trials.groups | map([.decision, .over])')" = '[["promote",true]]' ] || fail "the snapshot does not find the promote over: $(loop snapshot | jq -c .cost.trials.groups)"
  local ctl0; ctl0=$(cat "$ST/control.json")
  CONVEYOR_NOW=$(($(date +%s) + 50)) loop control pick small docs keep >/dev/null || fail "control pick small docs keep was refused"
  CARDCTL=$ctl0 fx_in 'SEATCARD=21; PICK=""; PICKSEAT=""; modelpick c1-21 21 2>/dev/null; jq -r .mode <<<"$PICK"'
  [ "$(jq -r '.rules.pick' "$ST/control.json") $(cat "$T/$CASE/run.out")" = 'on on' ] \
    || fail "a keep made after the card read its control record (CARDCTL: promote) did not keep the rule on: rules.pick and the card's mode: $(jq -c '[.rules.pick, .pickBack]' "$ST/control.json") $(cat "$T/$CASE/run.out")"
  CONVEYOR_NOW=$(($(date +%s) + 100)) loop control pick small docs promote >/dev/null || fail "control pick small docs promote was refused"
  fx_in 'SEATCARD=21; PICK=""; PICKSEAT=""; modelpick c1-21 21 2>/dev/null; jq -c "[.mode, .choice.model]" <<<"$PICK"'
  [ "$(cat "$T/$CASE/run.out")" = '["on","claude-sonnet-5-5"]' ] || fail "a snapshot built before the owner's new promote set the rule back: $(cat "$T/$CASE/run.out"); $(jq -c .rules.pick "$ST/control.json")"
}

# Bug caught (#1585 review): a step priced as an estimate counted as a measured cost in the cost check of the promoted
# choice, so a guess could set Pick settings back to Shadow. The promoted card's one build read only part of its usage
# (unread): it is priced at the tokens it counted, $4 (the picks table shows it), more than the $2 default card. The
# promoted side has no measured dollars, nothing is over, and the card picked keeps the rule on.
t_pickestimate() {
  setup "[$(issue 21 2026-01-01 | jq -c '.body = "Fix a typo in docs/guide.md."')]"
  tune '.models.allowed.claude += ["claude-sonnet-5-5"]'
  loop control rules pick=on >/dev/null && loop control pick small docs promote >/dev/null || fail "control rules pick=on or control pick was refused"
  pl c3-201 201 picked promoted
  pl c3-201 201 build promoted ok '{"tokens":{"claude":1000000,"codex":0},"usage":{"input":1000000,"write":0,"write1h":0,"read":0,"output":0},"model":"claude-opus-5-5","unread":"1 of 2 results hold no readable token usage"}'
  pl c3-201 201 landed promoted ok '{"sha":"s201","product":false}'; pcard c1-301 301 default claude-sonnet-5-5 landed
  # The picks row counts its step priced as an estimate, the default row none.
  local got; got=$(loop snapshot --fresh | jq -c '[(.cost.picks | map([.model, .usd, .estimate])), (.cost.trials.groups | map([.promoted.cards, .promoted.usd, .default.perLanded, .over]))]')
  [ "$got" = '[[["claude-sonnet-5-5",4,1],["m",2,0]],[[1,null,2,false]]]' ] || fail "the promoted card priced as an estimate ($ST/cards.jsonl) counted in the cost check, or its pick row does not count it: $got"
  fx_in 'SEATCARD=21; PICK=""; PICKSEAT=""; modelpick c1-21 21 2>/dev/null; jq -r .mode <<<"$PICK"'
  [ "$(jq -r .rules.pick "$ST/control.json") $(cat "$T/$CASE/run.out")" = 'on on' ] \
    || fail "an estimate set the rule back to shadow: rules.pick and the card's mode: $(jq -c '[.rules.pick, .pickBack]' "$ST/control.json") $(cat "$T/$CASE/run.out")"
}

# Bugs caught (#766): a card of a medium group in the share was a trial before the owner added the group, or was not
# one after; `control pick medium code add` was taken before the owner's decision on the small code trial result, or
# twice; a decision on a medium group was taken before it was added. Issue 30 (three Done-when items, split.doneWhen 3)
# is medium code; so is issue 35, picked after the owner added the group: issue 30's card has a line with its pick
# (the judge's seats line, pickjudge()), so a second pick of issue 30 would keep it, as a restart does.
t_pickaddgroup() {
  setup "[$(for n in 30 35; do issue $n 2026-01-01 | jq -c '.body = "Change src/a.js.\n\nDone when:\n- one\n- two\n- three"'; done | paste -sd, -)]"
  tune '.split.doneWhen = 3 | .models.allowed.claude += ["claude-sonnet-5-5"]'
  loop control rules pick=on >/dev/null || fail "control rules pick=on was refused"
  loop control pick medium code add >/dev/null 2>&1 && fail "control pick medium code add was taken before a decision on small code"
  loop control pick medium code keep >/dev/null 2>&1 && fail "a decision on medium code was taken before the group was added"
  pk='SEATCARD=30; PICK=""; PICKSEAT=""; modelpick c1-30 30 2>/dev/null; jq -r "\"\(.group) \(.trial) \(.choice.model)\"" <<<"$PICK"; seat builder | jq -r .model'
  fx_in "$pk"
  [ "$(cat "$T/$CASE/run.out")" = $'medium code false m\nm' ] || fail "a card of a medium group not added did not get the defaults: $(cat "$T/$CASE/run.out")"
  loop control pick small code keep >/dev/null && loop control pick medium code add >/dev/null || fail "control pick medium code add was refused after a decision on small code"
  loop control pick medium code add >/dev/null 2>&1 && fail "control pick medium code add was taken twice"
  fx_in "${pk//30/35}"
  [ "$(cat "$T/$CASE/run.out")" = $'medium code true claude-sonnet-5-5\nclaude-sonnet-5-5' ] || fail "the card in the share of an added medium group is no trial: $(cat "$T/$CASE/run.out")"
}

# Bugs caught (#766): `control pick <group> next` was taken on a group not promoted; after next, a promoted card left
# the promoted challenger, the card in the share was no trial of the next one (Sonnet 5.5 at low effort), or the
# snapshot named the old challenger and counted its trial cards with the new one's; a drop did not go back to the
# promoted challenger, with no trials. Issue 21 is out of the share, 25 in it; both are small docs. The snapshot's
# cards: c1-101, an older trial at medium effort, and c1-102, a trial at low effort.
t_picknext() {
  setup "[$(for n in 21 25; do issue $n 2026-01-01 | jq -c '.body = "Fix a typo in docs/guide.md."'; done | paste -sd, -)]"
  tune '.models.allowed.claude += ["claude-sonnet-5-5"]'
  loop control rules pick=on >/dev/null || fail "control rules pick=on was refused"
  loop control pick small docs next >/dev/null 2>&1 && fail "control pick small docs next was taken on a group not promoted"
  loop control pick small docs promote >/dev/null && loop control pick small docs next >/dev/null || fail "control pick small docs next was refused after promote"
  [ "$(jq -c '.picks["small docs"] | [.decision, .promoted, .challenger]' "$ST/control.json")" = '["next",{"model":"claude-sonnet-5-5","effort":"medium"},{"model":"claude-sonnet-5-5","effort":"low"}]' ] \
    || fail "next did not put the next challenger on trial beside the promoted one: $(jq -c .picks "$ST/control.json")"
  pk='for n in 21 25; do SEATCARD=$n; PICK=""; PICKSEAT=""; modelpick c1-$n $n 2>/dev/null; echo "$n $(jq -r "\"\(.trial) \(.promoted // false) \(.choice.effort)\"" <<<"$PICK") $(seat builder | jq -r "\"\(.model) \(.effort)\"")"; done'
  fx_in "$pk"
  [ "$(cat "$T/$CASE/run.out")" = $'21 false true medium claude-sonnet-5-5 medium\n25 true false low claude-sonnet-5-5 low' ] || fail "the cards of a group with its next challenger on trial: $(cat "$T/$CASE/run.out")"
  pcard c1-101 101 trial claude-sonnet-5-5 landed
  x='{"pick":{"choice":{"effort":"low"}}}'; pl c1-102 102 picked trial; pl c1-102 102 build trial ok "$x"; pl c1-102 102 landed trial ok '{"sha":"s102","product":false,"pick":{"choice":{"effort":"low"}}}'
  # The trial cards at low effort: c1-102 and c1-25, whose pick above wrote its line (the judge's seats line, pickjudge()).
  [ "$(loop snapshot --fresh | jq -c '.cost.trials.groups | map([.model, .effort, .trial.cards])')" = '[["claude-sonnet-5-5","low",2]]' ] \
    || fail "the snapshot's group does not show the next challenger and its trial cards only: $(loop snapshot | jq -c .cost.trials.groups)"
  loop control pick small docs drop >/dev/null || fail "control pick small docs drop was refused"
  fx_in "$pk"
  [ "$(cat "$T/$CASE/run.out")" = $'21 false true medium claude-sonnet-5-5 medium\n25 false false medium m medium' ] || fail "a drop of the next challenger did not go back to the promoted one: $(cat "$T/$CASE/run.out")"
}

# Bugs caught (#766): while the next challenger was on trial, the return to Shadow told the owner to choose keep or
# drop, which both leave the costly promoted choice in force; after the owner promoted the next challenger (Sonnet 5.5
# at low effort) in place of the first, the cost check pooled the promoted cards of both choices, so the first one's
# cost could send the cheaper choice back to Shadow; a retry of an issue whose card blocked on the replaced choice
# charged that run's spend to the choice promoted now. Cards: c1-301, a default card on a $2 build; c1-201, a
# promoted card at medium effort on a $4 build; c1-200, a promoted card of issue 202 at medium effort, blocked after a
# $4 build; c1-202, its retry, a promoted card at low effort that lands on a $2 build.
t_pickbacknext() {
  setup "[$(issue 21 2026-01-01 | jq -c '.body = "Fix a typo in docs/guide.md."')]"
  loop control rules pick=on >/dev/null && loop control pick small docs promote >/dev/null && loop control pick small docs next >/dev/null || fail "control rules pick=on, promote or next was refused"
  pcard c1-301 301 default claude-sonnet-5-5 landed; pcard c1-201 201 promoted claude-opus-5-5 landed
  [ "$(loop snapshot --fresh | jq -c '.cost.trials.groups | map([.over, .back])')" = '[[true,"Promoted cards of small docs on claude-sonnet-5-5 at medium effort cost $4.00 for each landed card, more than the $2.00 of its default cards. Conveyor set Pick settings to Shadow. Before you set it to On again, choose promote or drop for the group. promote builds on claude-sonnet-5-5 at low effort in its place: conveyor.sh control pick small docs promote. drop, two times, ends the trials and builds on the defaults: conveyor.sh control pick small docs drop, then conveyor.sh control pick small docs drop."]]' ] \
    || fail "the return to Shadow while the next challenger is on trial names commands that keep the promoted choice: $(loop snapshot | jq -c '.cost.trials.groups | map([.over, .back])')"
  # The two drops the line names end the costly choice.
  loop control pick small docs drop >/dev/null && loop control pick small docs drop >/dev/null || fail "control pick small docs drop was refused"
  [ "$(loop snapshot --fresh | jq -c '[.cost.trials.groups[] | .over]')" = '[false]' ] && [ "$(jq -r '.picks["small docs"].decision' "$ST/control.json")" = drop ] || fail "two drops left the costly choice promoted: $(jq -c .picks "$ST/control.json")"
  # The promote the line names ends it too, and the cards of the replaced choice no longer count.
  loop control pick small docs promote >/dev/null && loop control pick small docs next >/dev/null && loop control pick small docs promote >/dev/null || fail "control pick small docs promote, next, promote was refused"
  pcard c1-200 202 promoted claude-opus-5-5 blocked
  pl c1-202 202 picked promoted
  pl c1-202 202 build promoted ok '{"tokens":{"claude":1000000,"codex":0},"usage":{"input":1000000,"write":0,"write1h":0,"read":0,"output":0},"model":"claude-sonnet-5-5","pick":{"choice":{"effort":"low"}}}'
  pl c1-202 202 landed promoted ok '{"sha":"s202","product":false,"pick":{"choice":{"effort":"low"}}}'
  [ "$(loop snapshot --fresh | jq -c '.cost.trials.groups | map([.effort, .promoted.cards, .promoted.perLanded, .over])')" = '[["low",1,2,false]]' ] \
    || fail "the cost check pooled the promoted cards or runs of the replaced choice: $(loop snapshot | jq -c .cost.trials.groups)"
}

# Bugs caught (#766): a judge or reviewer the owner promoted with no replay result of it was taken; once the owner
# promoted a judge from its replay result, a card of the rule On that is no trial did not have it as its judge, or
# its pick did not record it; a trial card's judge left the default; the judge was used before the promote. Issue 21
# is out of the share, 25 in it; both are small docs. The replay line is the one replay() writes, cut to the fields read.
t_pickseats() {
  setup "[$(for n in 21 25; do issue $n 2026-01-01 | jq -c '.body = "Fix a typo in docs/guide.md."'; done | paste -sd, -)]"
  tune '.models.allowed.claude += ["claude-sonnet-5-5"] | .models.allowed["claude-reviewer"] += ["m2"]'
  loop control rules pick=on >/dev/null || fail "control rules pick=on was refused"
  pk='for n in 21 25; do SEATCARD=$n; PICK=""; PICKSEAT=""; PICKSEATS=""; modelpick c1-$n $n 2>/dev/null; echo "$n $(jq -c "[.trial, .seats]" <<<"$PICK") $(seat judge | jq -r "\"\(.model) \(.effort)\"")"; done'
  fx_in "$pk"; before=$(cat "$T/$CASE/run.out")
  case $before in *m2*) fail "the fixture's default judge is m2, so the case cannot tell the promoted one: $before" ;; esac
  # Bug caught (#862): the refusal told the owner to run `pick replay <seat> <model>`, which for the reviewer is a
  # usage error (replay() runs only the judge) and for the judge dropped the effort asked.
  r=$(loop control pick judge promote m2 high 2>&1 >/dev/null) && fail "control pick judge promote m2 was taken with no replay result"
  [[ $r == *"run conveyor.sh pick replay judge m2 high first"* ]] || fail "the judge refusal does not name the replay for its model and effort: $r"
  jq -cn '{time: "2026-11-01T00:00:00Z", seat: "judge", model: "m2", effort: "high", last: 20, reviews: 3}' >> "$ST/replays.jsonl"
  r=$(loop control pick reviewer promote m2 2>&1 >/dev/null) && fail "control pick reviewer promote m2 was taken on a judge replay result"
  [[ $r == *"no reviewer replay to run"* && $r != *"pick replay reviewer"* ]] || fail "the reviewer refusal names a replay command that cannot run: $r"
  loop control pick judge promote m2 >/dev/null || fail "control pick judge promote m2 was refused after its replay result"
  fx_in "$pk"
  d=$(sed -n 2p <<<"$before" | cut -d' ' -f3-)
  [ "$(cat "$T/$CASE/run.out")" = "21 [false,{\"judge\":{\"model\":\"m2\",\"effort\":\"high\"}}] m2 high
25 [true,null] $d" ] || fail "the judge seat of a card that is no trial and of a trial card, after the promote: $(cat "$T/$CASE/run.out"); before it: $before"
  fx_in 'SEATCARD=21; PICK=""; PICKSEATS=""; modelpick c1-21 21 2>/dev/null; jq -cn --argjson p "$PICK" "{card: \"c1-21\", issue: 21, step: \"worktree\", time: \"2026-11-01T00:00:00Z\", tokens: {claude: 0, codex: 0}, result: \"ok\", sha: \"\", reason: \"\", pick: \$p}"'
  recok "$T/$CASE/run.out" "a pick with a promoted judge"
}
