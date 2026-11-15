#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: the snapshot, the live cost and the track.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# Bugs: the snapshot leaves out one of the fields the Conveyor views show, names a card's step differently
# from `cards`, prices a card from a table of its own, counts a card closed long ago in today's or the week's
# figures, lists an issue pick would not take (or in another order), or gives no record at all when gh is down, or
# when the price table cannot be run; its parts read the records at different moments, so a card recorded while it
# is built is in one part and not another; a retried card's spend drops out of the totals.
# Each snapshot case below starts from these records and issues: one after another, its 20 snapshots were one 9 s case.
snapshotstart() {
  export TZ=UTC; setup '[]'; S=$ST; mkdir -p "$S"; d=$(date -u +%F)
  seatset model claude-sonnet-5-5; seatset reviewer gpt-6.1-sol
  pushed=$(git -C "$R" rev-parse HEAD); echo x > "$R/n.txt"; git -C "$R" add -A; git -C "$R" commit -qm next; ahead=$(git -C "$R" rev-parse HEAD)
  # One card per call: its steps in order, a minute apart from <day>T00:00. A session is $2 at list price, a review $1.
  B='{"tokens":{"claude":1000000,"codex":0},"usage":{"input":1000000,"write":0,"write1h":0,"read":0,"output":0},"model":"claude-sonnet-5-5"}'
  V='{"tokens":{"claude":0,"codex":500000},"usage":{"input":500000,"read":0,"output":0},"visible":"no","model":"gpt-6.1-sol"}'
  card() { # <issue> <day> <step[:result[:extra json]]>...
    local n=$1 day=$2 m=0 a step res x; shift 2
    for a; do
      IFS=: read -r step res x <<<"$a"
      case $step in picked) x="{\"title\":\"T$n\"}" ;; build|fix) x=${x:-$B} ;; review) x=${x:-$V} ;; test) x='{"sec":60,"usage":{"input":0,"write":0,"write1h":0,"read":0,"output":0}}' ;; esac
      jq -cn --arg c "c$n" --argjson i "$n" --arg s "$step" --arg t "$(printf '%sT00:%02d:00Z' "$day" "$m")" --arg r "${res:-ok}" --argjson x "${x:-{\}}" \
        '{card:$c,issue:$i,step:$s,time:$t,tokens:{claude:0,codex:0},result:$r,sha:"",reason:""} * $x' >> "$S/cards.jsonl"
      m=$((m + 1))
    done
  }
  card 1 "$d" picked
  card 2 "$d" picked worktree brief
  card 3 "$d" picked worktree brief build
  card 4 "$d" picked worktree brief build review:NO-GO
  card 5 "$d" picked worktree brief build review:GO
  card 6 "$d" picked worktree brief build review:GO test:pass
  card 7 "$d" picked worktree brief build 'review:GO:{"tokens":{"claude":0,"codex":500000},"usage":{"input":500000,"read":0,"output":0},"visible":"yes: a new button","model":"gpt-6.1-sol"}' \
    'blocked:blocked:{"reason":"visible to customers or staff: needs Dana'"'"'s yes: a new button [this could not be posted on the issue]"}'
  card 8 "$d" picked worktree brief build 'blocked:blocked:{"reason":"review 1: no answer"}'
  card 9 "$d" picked worktree brief build review:GO test:pass "landed:ok:{\"sha\":\"$pushed\",\"product\":false}"
  card 10 "$d" picked worktree brief build review:NO-GO fix review:NO-GO fix review:NO-GO test:pass "landed:ok:{\"sha\":\"$ahead\",\"product\":true,\"leftover\":true,\"followups\":[100101,100102]}"
  card 11 "$(date -u -d '3 days ago' +%F)" picked worktree brief build review:NO-GO fix review:GO test:pass 'landed:ok:{"sha":"abc","product":false}'
  card 12 "$(date -u -d '10 days ago' +%F)" picked worktree brief build review:GO test:pass 'landed:ok:{"sha":"abd","product":false}'
  card 13 "$d" picked worktree brief build review:GO 'closed:ok:{"reason":"ALREADY-DONE: a.txt"}'
  # Card 12 was made by land-branch: its picked line names the branch.
  jq -c 'if .card == "c12" and .step == "picked" then .branch = "fast-12" else . end' "$S/cards.jsonl" > "$STUB/c" && mv "$STUB/c" "$S/cards.jsonl"
  # The open issues: 8 has a card; 22 and 23 are held by the control record (their backlog and dormant labels hold
  # nothing); 24 is a follow-up given its label by hand; 12 more qualify.
  # 25, 26 and 27 are labelled awaiting-deploy: in neither next nor held, though 26 is backlog and 27 a
  # follow-up. GitHub says when 25 got the label (the later of two times) and says nothing of 26 and 27.
  loop control hold 22 23 >/dev/null
  { issue 8 2026-01-01 backlog; issue 20 2026-02-02 P1; issue 21 2026-02-01 P2; issue 22 2026-01-01 backlog P0; issue 23 2026-01-01 backlog dormant
    issue 24 2026-03-01 conveyor-followup backlog; issue 27 2026-01-01 conveyor-followup awaiting-deploy P0; issue 26 2026-01-01 awaiting-deploy backlog P0; issue 25 2026-01-01 awaiting-deploy
    for i in 30 31 32 33 34 35 36 37 38 39; do issue $i 2026-04-$i; done; } | jq -cs . > "$STUB/issues.json"
  echo '{"data":{"repository":{"issues":{"nodes":[{"number":25,"timelineItems":{"nodes":[{"createdAt":"2026-11-02T00:00:00Z","label":{"name":"awaiting-deploy"}},
    {"createdAt":"2026-11-05T00:00:00Z","label":{"name":"awaiting-deploy"}},{"createdAt":"2026-11-07T00:00:00Z","label":{"name":"P1"}}]}},{"number":26,"timelineItems":{"nodes":[]}}]}}}}' > "$STUB/labelled"
  q() { jq -c "$1" <<<"$out"; }
}
t_snapshot() { snapshotstart
  out=$(loop snapshot) || fail "snapshot exited non-zero"
  [ "$(q .awaitingDeploy)" = '[{"issue":25,"title":"title 25","since":"2026-11-05T00:00:00Z"},{"issue":26,"title":"title 26","since":null},{"issue":27,"title":"title 27","since":null}]' ] \
    || fail "awaitingDeploy: $(q .awaitingDeploy)"
  # A land-branch card that landed 10 days ago is in neither landed nor cost.cards, and still in branches.
  [ "$(q '[.branches, ([.landed[], .cost.cards[]] | map(.card) | index("c12"))]')" = "[[{\"card\":\"c12\",\"issue\":12,\"title\":\"T12\",\"step\":\"landed\",\"time\":\"$(date -u -d '10 days ago' +%F)T00:06:00Z\"}],null]" ] \
    || fail "branches: $(q .branches)"
  # #4042: card 12, landed 10 days ago, is in pushedCards once its push is recorded today, and not before.
  [ "$(q '.pushedCards | map(select(.card == "c12"))')" = '[]' ] || fail "an unpushed card is in pushedCards: $(q .pushedCards)"
  [ "$(q '[.day, (.time | fromdate > 0)]')" = "[\"$d\",true]" ] || fail "day or time: $out"
  # Each card there also carries its reviews and its track: t_track holds what they say.
  [ "$(q '.needsYou | [.waiting[], .blocked[]] | map([(.reviews | length), (.track.steps | length), (.track.detail | length)])')" = '[[1,6,17],[0,6,17]]' ] || fail "a card that needs the owner lacks its reviews or its track: $(q .needsYou)"
  # A pack that names a commit has no refused engine commit to show (t_followrefuse holds one that follows main).
  [ "$(q '.needsYou.engine')" = null ] || fail "needsYou.engine is not null for a pack that names a commit: $(q .needsYou.engine)"
  # No run of the test rules was held by their burst guard (t_rulesburst holds one).
  [ "$(q '.needsYou.testRules')" = null ] || fail "needsYou.testRules is not null with no test rule run: $(q .needsYou.testRules)"
  # No open issue names a dependency in another repository: farDeps is an empty list (t_fardepsfail holds one).
  [ "$(q '.needsYou | del(.before, .pipeline, .engine, .testRules) | map_values(map(del(.reviews, .track, .metrics, .parent, .start, .pickedAt, .priorSec, .totalSec, .earlier)))')" = "{\"waiting\":[{\"card\":\"c7\",\"issue\":7,\"title\":\"T7\",\"sentence\":\"a new button\",\"since\":\"${d}T00:05:00Z\",\"doneWhen\":null,\"stalls\":0,\"files\":{\"count\":null,\"paths\":null}}],\"blocked\":[{\"card\":\"c8\",\"issue\":8,\"title\":\"T8\",\"reason\":\"review 1: no answer\",\"tail\":\"\",\"since\":\"${d}T00:04:00Z\",\"doneWhen\":null,\"stalls\":0}],\"farDeps\":[]}" ] \
    || fail "needsYou: $(q .needsYou)"
  [ "$(q '.belt | map("\(.card) \(.issue) \(.title) \(.step) \(.review) \(.of) \(.stepAt[14:16]) \(.model) \(.tokens.claude) \(.tokens.codex) \(.usd) \(.reading)") | join(", ")')" \
    = '"c1 1 T1 brief null 3 00 null 0 0 null false, c2 2 T2 build null 3 02 claude-sonnet-5-5 0 0 null false, c3 3 T3 review 1 3 03 gpt-6.1-sol 1000000 0 2 true, c4 4 T4 fix null 3 04 claude-sonnet-5-5 1000000 500000 3 true, c5 5 T5 tests null 3 04 null 1000000 500000 3 true, c6 6 T6 landing null 3 05 null 1000000 500000 3 true, c10 10 T10 push null 3 10 null 3000000 1500000 9 true"' ] \
    || fail "belt: $(q .belt)"
  # A card that has landed stays on the belt, after the open ones, until it is pushed and its issue is closed:
  # card 10's commit is not at origin, so its push is the step in progress, in the belt and in the landed list alike.
  # Card 9 (pushed, with no marks: it landed before they were recorded) is not held there.
  [ "$(q '[(.belt | map(.landed)), (.belt[-1].track | [.detailAt, .label, (.detail[12:16] | map(.state))]), (.landed[] | select(.card == "c10") | .track | [.detailAt, .detail[14].state])]')" \
    = '[[false,false,false,false,false,false,true],[14,"pushing",["skipped","done","now","todo"]],[14,"now"]]' ] \
    && [ "$(q '[(.belt[-1].track | [.at, (.steps | map(.state[0:1]) | join(""))]), (.landed[] | select(.card == "c10") | .track | [.at, .steps[5].state])]')" = '[[5,"dddddn"],[5,"now"]]' ] || fail "a landed card that is not pushed yet: $(q '.belt[-1]')"
  [ "$(q '.queue | {next}')" = "$(jq -cn '{next: ([[24, "P3", true], [20, "P1", false], [21, "P2", false]] + ([range(30; 37)] | map([., "P3", false]))
    | map({issue: .[0], title: "title \(.[0])", priority: .[1], followup: .[2], retried: false, parent: null}))}')" ] || fail "queue: $(q .queue)"
  # Every open issue: the ones not queued are held, each with why; the four counts add up to the open issues.
  [ "$(q '.open | [.count, .split, (.held | map([.issue, (.reasons | map(.label // .step // .kind) | join(","))]))]')" \
    = '[19,{"queued":13,"you":2,"labelOrRule":4,"belt":0},[[8,"blocked"],[22,"you"],[23,"you"],[27,"awaiting-deploy"],[26,"awaiting-deploy"],[25,"awaiting-deploy"]]]' ] \
    || fail "the open issues and why each is held: $(q .open)"
  # And every open issue, queued, held or on the belt, with its labels and age: the Rules tab lists them all, so an
  # issue missing here is one the owner cannot find or manage there.
  [ "$(q '.open.issues | [length, (map(.issue) == (map(.issue) | sort)), (.[] | select(.issue == 22 or .issue == 20) | [.issue, .priority, .labels, .created])]')" \
    = '[19,true,[20,"P1",["P1"],"2026-02-02"],[22,"P0",["backlog","P0"],"2026-01-01"]]' ] || fail "the snapshot does not list every open issue: $(q .open.issues)"
  # The whole queue: next is its first ten, each with its createdAt; the control record holds 22 and 23 and skips nothing.
  [ "$(q '.queue | [((.order[:10] | map(del(.created, .areas, .since))) == (.next | map(del(.parent))) and (.order | all(.areas == [])) and (.order[:3] | map(.created)) == ["2026-03-01","2026-02-02","2026-02-01"]), (.order | map(.issue)), (.holding | map(.issue)), .skipped]')" = '[true,[24,20,21,30,31,32,33,34,35,36,37,38,39],[22,23],[]]' ] || fail "the whole queue: $(q .queue)"
  [ "$(q '.landed | map("\(.card) \(.issue) \(.title) \(.step) \(.time[14:16]) \(.usd | numbers + 0) \(.reviews) \(.followups | tojson) \(.sha == "'"$ahead"'") \(.pushed)") | join(", ")')" \
    = '"c10 10 T10 landed 10 9 3 [100101,100102] true false, c9 9 T9 landed 06 3 1 [] false true, c13 13 T13 closed 05 3 1 [] false null"' ] || fail "landed: $(q .landed)"
  [ "$(q '.health | [.builderCap, .models, (.waiting | map(.issue)), (.blocked | map(.issue)), (.unpushed | map(.issue)), .loop, .gh, (.diskFreeKb > 0)]')" \
    = '[5,{"claude":"claude-sonnet-5-5","codex":"gpt-6.1-sol"},[7],[8],[10],false,true,true]' ] || fail "health: $(q .health)"
  # The time, free disk and machine load are read again by each call, and the load moves between them on a busy machine.
  [ "$(q '.health | del(.time, .diskFreeKb, .machineNow.load)')" = "$(loop health | jq -c 'del(.time, .diskFreeKb, .machineNow.load)')" ] || fail "health is not the health record"
  [ "$(q '.cost | del(.cards)')" = '{"today":31,"todayLeftOut":0,"week":37,"weekLeftOut":0,"perLanded":5.25,"perLandedLeftOut":0,"landedAfter":{"1":2,"2":1,"3":1,"more":0},"unpricedSteps":0,"unpriced":[]}' ] || fail "cost: $(q .cost)"
  # Per card, the 7 days: a card landed on an earlier day (11) and the blocked ones (7, 8) are rows; one with no step
  # ended (1, 2) or last worked on before the 7 days (12) is not. The rows add up to the totals.
  [ "$(q '.cost.cards | map("\(.issue) \(.state) \(.today) \(.week)") | sort | join(", ")')" \
    = '"10 landed 9 9, 11 landed 0 6, 13 closed 3 3, 3 on the belt 2 2, 4 on the belt 3 3, 5 on the belt 3 3, 6 on the belt 3 3, 7 blocked 3 3, 8 blocked 2 2, 9 landed 3 3"' ] \
    && [ "$(q '.cost.cards | [.[0].card, .[-1].card, (map(.today) | add), (map(.week) | add), (.[0] | keys_unsorted)]')" = '["c10","c11",31,37,["card","issue","title","state","runs","today","week"]]' ] \
    || fail "cost per card: $(q .cost.cards)"
}
# GitHub does not say when: the same list, every since null. No issue carries the label: an empty list.
t_snapshotdeploy() { snapshotstart
  rm "$STUB/labelled"; [ "$(loop snapshot | jq -c '.awaitingDeploy | map([.issue, .since])')" = '[[25,null],[26,null],[27,null]]' ] || fail "awaitingDeploy without the label times"
  jq -c 'map(select(.labels | any(.name == "awaiting-deploy") | not))' "$STUB/issues.json" > "$STUB/issues.none" && mv "$STUB/issues.none" "$STUB/issues.json"
  [ "$(loop snapshot | jq -c .awaitingDeploy)" = '[]' ] || fail "awaitingDeploy with no such issue is not an empty list"
  mkdir "$STUB/tmp"; TMPDIR=$STUB/tmp loop snapshot >/dev/null 2>&1; [ -z "$(ls -A "$STUB/tmp")" ] || fail "a snapshot left its copy of the records behind: $(ls -A "$STUB/tmp")"
  echo junk >> "$S/cards.jsonl"; loop snapshot >/dev/null 2>&1 && fail "a snapshot was given over records that do not check"; :
}
# #4042: card 12, landed 10 days ago, is in pushedCards once its push is recorded today (t_snapshot: not before).
t_snapshotpushed() { snapshotstart; card 12 "$d" 'pushed:ok:{"sha":"abd","sec":5,"head":"abd"}'
  [ "$(loop snapshot | jq -c '.pushedCards | map(select(.card == "c12"))')" = "[{\"card\":\"c12\",\"issue\":12,\"time\":\"${d}T00:00:00Z\",\"day\":\"$d\"}]" ] \
    || fail "a card landed 10 days ago and pushed today is not in pushedCards: $(loop snapshot | jq -c .pushedCards)"
}
# A card's steps keep what the owner reads there: a NO-GO review its findings, and the blocked line its sentence and
# the end of its output, newlines kept. Without them the steps show only names, and the findings are lost.
# The Board draws the steps on a time axis and a review with its findings: each step has the time it ended (the
# queue's at the pick-up), and a review its counts. Without them the bars have no clock times and no findings chip.
t_snapshotsteps() { snapshotstart
  card 14 "$d" picked worktree brief build 'review:NO-GO:{"reason":"[P1] a.sh:1 wrong\n[P2] b.sh:2 slow","tail":"[P1] a.sh:1 wrong\n[P2] b.sh:2 slow","visible":"no","counts":{"P0":0,"P1":1,"P2":1,"P3":0}}' 'blocked:blocked:{"reason":"the changed tests failed; nothing landed.","tail":"ok 1\nFAIL x.test"}'
  out=$(loop snapshot) || fail "snapshot exited non-zero"
  [ "$(q '.needsYou.blocked[] | select(.card == "c14") | .track.records | map(select(.name | IN("review 1 (NO-GO)", "stopped")) | {name, why, output})')" \
    = '[{"name":"review 1 (NO-GO)","why":null,"output":"[P1] a.sh:1 wrong\n[P2] b.sh:2 slow"},{"name":"stopped","why":"the changed tests failed; nothing landed.","output":"ok 1\nFAIL x.test"}]' ] \
    || fail "a card's steps lack a NO-GO review's findings or a blocked line's sentence and output: $(q '.needsYou.blocked[] | select(.card == "c14") | .track.records')"
  [ "$(q '.needsYou.blocked[] | select(.card == "c14") | .track.records | map([.name, .at[11:16], .counts.P1])')" \
    = '[["queued","00:00",null],["picked","00:00",null],["worktree ready","00:01",null],["brief written","00:02",null],["building","00:03",null],["review 1 (NO-GO)","00:04",1],["stopped","00:05",null]]' ] \
    || fail "a card's steps lack their end times or a review its counts: $(q '.needsYou.blocked[] | select(.card == "c14") | .track.records')"
}
# The snapshot and `cards` read the same rows: a review after a fix is review 2, and both call the step a review.
t_snapshotcards() { snapshotstart
  card 4 "$d" fix; mv "$S/cards.jsonl" "$S/all"; grep '"card":"c4"' "$S/all" > "$S/cards.jsonl"
  [ "$(loop snapshot | jq -c '.belt | map([.step, .review, .usd + 0])')" = '[["review",2,5]]' ] && [ "$(loop cards | jq -r '.cards[0].step')" = review ] && ! loop cards | grep -q '"x"' \
    || fail "review 2 of 3, or cards gained the snapshot's fields: $(loop snapshot | jq -c .belt)"
}
# A step is priced at the model its own line names, never at the one in force now (the builder moved from Fable
# to Opus, and every earlier Fable session read at Opus rates). Card 4's lines name no model, card 6's build names
# one with no price: those 3 steps are unpriced, each says why, and the totals are the priced steps' with the 3 left
# out counted; a card with an unpriced step has no dollars of its own, never the sum of the rest. A model in force
# with no price prices nothing differently. A failed gh leaves the queue null.
t_snapshotprice() { snapshotstart
  cp "$S/cards.jsonl" "$STUB/cards.priced"
  jq -c 'if .card == "c4" then del(.model) elif .card == "c6" and .step == "build" then .model = "m" else . end' "$STUB/cards.priced" > "$S/cards.jsonl"
  seatset model m; echo junk > "$STUB/issues.json"
  out=$(loop snapshot 2>/dev/null) || fail "snapshot without gh exited non-zero"
  [ "$(q .awaitingDeploy)" = null ] && [ "$(q .open)" = null ] || fail "awaitingDeploy or open when the issues were not listed: $(q '[.awaitingDeploy, .open]')"
  [ "$(q '[.queue, .cost.today, .cost.todayLeftOut, .cost.week, .cost.weekLeftOut, .cost.perLanded, .cost.perLandedLeftOut, .cost.unpricedSteps, .belt[2].usd, .belt[3].usd, (.needsYou.waiting | length), (.cost.cards | map(select(.week == null) | .issue) | sort)]')" \
    = '[{"next":null,"order":null,"holding":null,"skipped":null,"waiting":null},26,3,32,3,5.25,0,3,2,null,1,[4,6]]' ] \
    || fail "unpriced steps or a failed issue list: $(q '[.cost, .belt[3]]')"
  [ "$(q '.cost.unpriced | map("\(.card) \(.step) \(.why)") | sort | join(", ")')" = '"c4 build no model recorded, c4 review no model recorded, c6 build no price for its model: m"' ] \
    || fail "the unpriced steps do not say why: $(q .cost.unpriced)"
  cp "$STUB/cards.priced" "$S/cards.jsonl"
  # The price table cannot be run at all: the same record, with no dollars anywhere. Only the price table fails: the
  # engine's own state helper (state.py) runs on Python too.
  mkdir "$STUB/nopy"; printf '#!/bin/sh\ncase "$*" in *dashboard_limit.py*) exit 1 ;; esac\nexec %s "$@"\n' "$(command -v python3)" > "$STUB/nopy/python3"; chmod +x "$STUB/nopy/python3"
  out=$(PATH=$STUB/nopy:$PATH loop snapshot 2>/dev/null) || fail "snapshot exited non-zero when the price table could not be run"
  [ "$(q '[.cost.today, .cost.week, .cost.perLanded, .belt[2].usd, (.belt | length), (.landed | map(.usd)), .landed[0].pushed]')" = '[null,null,null,null,7,[null,null,null],false]' ] \
    || fail "the price table could not be run: $out"
}
# The cases below go on with GitHub's issue list failing, as the case above leaves it, and card 5's landing ($STUB/late).
latestart() {
  snapshotstart; echo junk > "$STUB/issues.json"
  jq -cn --arg t "${d}T00:30:00Z" --arg s "$ahead" '{card:"c5",issue:5,step:"landed",time:$t,tokens:{claude:0,codex:0},result:"ok",sha:$s,reason:"",product:false}' > "$STUB/late"
  mark() { jq -cn --arg c "c$1" --argjson i "$1" --arg s "$2" --arg t "$3" --arg r "$4" --arg sha "${5:-}" '{card:$c,issue:$i,step:$s,time:$t,tokens:{claude:0,codex:0},result:$r,sha:$sha,reason:""}' >> "$S/cards.jsonl"; }
  after() { q '[.belt[] | select(.landed) | [.card, .step, .track.detailAt, .track.label, (.track.detail[14:16] | map(.state[0:1]) | join("")), .track.steps[5].state[0:1], .track.reason]]'; }
}
# One read: a card that lands while the snapshot is built (here as health asks gh) is in no part of that snapshot.
t_snapshotlate() { latestart
  echo '[ -e "$STUB/was-late" ] || { cat "$STUB/late" >> "$ST/cards.jsonl"; : > "$STUB/was-late"; }' > "$STUB/status-cmd"
  out=$(loop snapshot 2>/dev/null) || fail "snapshot exited non-zero when a card landed as it was built"
  grep -q '"card":"c5".*"landed"' "$S/cards.jsonl" || fail "the test's late landing was not written"
  [ "$(q '[(.belt | map(.card) | index("c5") != null), (.landed | map(.card)), (.health.unpushed | map(.card)), .health.newest[11:16]]')" = '[true,["c10","c9","c13"],["c10"],"00:05"]' ] \
    || fail "a card that landed while the snapshot was built is in part of it: $out"
  out=$(loop snapshot 2>/dev/null); [ "$(q '[(.landed | map([.card, .pushed])), (.health.unpushed | map(.card))]')" = '[[["c5",false],["c10",false],["c9",true],["c13",null]],["c10","c5"]]' ] \
    || fail "the next snapshot does not hold the landed card whole: $out"
  # A blocked card given back with `retry` leaves the views; what it cost stays in today's and the week's dollars.
  [ "$(q '.cost | [.today, .week]')" = '[31,37]' ] || fail "cost before the retry: $(q .cost)"
  loop retry 8 >/dev/null || fail "retry of the blocked #8 failed"
  out=$(loop snapshot 2>/dev/null) || fail "snapshot after a retry exited non-zero"
  [ "$(q '[(.cost | del(.cards)), .needsYou.blocked, (.health.blocked | length), ([.belt[], .landed[]] | map(.card) | index("c8")), (.cost.cards[] | select(.card == "c8") | [.state, .today, .week])]')" \
    = '[{"today":31,"todayLeftOut":0,"week":37,"weekLeftOut":0,"perLanded":4.8,"perLandedLeftOut":0,"landedAfter":{"1":3,"2":1,"3":1,"more":0},"unpricedSteps":0,"unpriced":[]},[],0,null,["retried",2,2]]' ] || fail "a retried card's spend left the totals, or the card is still shown: $out"
  # The rest of a landed card's track. Cards 10 and 5 landed and are not at origin: both are on the belt, pushing.
  [ "$(after)" = '[["c10","push",14,"pushing","nt","n",null],["c5","push",14,"pushing","nt","n",null]]' ] || fail "two landed cards waiting for their push: $(after)"
}
# From where the case above ends: card 5 landed, the blocked #8 retried.
t_snapshotpush() { latestart; cat "$STUB/late" >> "$S/cards.jsonl"; loop retry 8 >/dev/null || fail "retry of the blocked #8 failed"
  # A push that fails after they landed is their step failed, not a card gone from the belt.
  mark 5 push "${d}T00:40:00Z" fail "$ahead"; out=$(loop snapshot 2>/dev/null) || fail "snapshot after a failed push exited non-zero"
  [ "$(after)" = '[["c10","push",14,"push failed; it is tried again","ft","f",""],["c5","push",14,"push failed; it is tried again","ft","f",""]]' ] || fail "a failed push is not the failed step of the cards it carried: $(after)"
  # Its step in "Every step" has the time of the card's last line, so the Board keeps every bar on the clock (one
  # bar without a time draws them all without their clock times and pauses).
  [ "$(q '.belt[] | select(.card == "c5") | .track.records[-1] | [.name, .state, .at[11:16]]')" = '["push failed; it is tried again","failed","00:30"]' ] \
    || fail "a failed push has no time in the card's steps: $(q '.belt[] | select(.card == "c5") | .track.records[-1]')"
  # The push works. Card 5's pushed mark is new: it stays on the belt while GitHub closes its issue. Card 10's is an
  # hour old with no issue line (the loop died before it wrote one): while its issue may still be open (the open
  # issues could not be listed here) it stays on the belt, Push failed, not lost; it leaves once its issue is closed.
  echo "$ahead origin main" > "$S/pushed"; mark 10 pushed "$(date -u -d '1 hour ago' +%FT%TZ)" ok "$ahead"; mark 5 pushed "$(date -u +%FT%TZ)" ok "$ahead"
  out=$(loop snapshot 2>/dev/null) || fail "snapshot after the push exited non-zero"
  [ "$(after)" = '[["c10","issue",15,"GitHub did not close the issue","df","f","GitHub did not close the issue: no close of it was recorded"],["c5","issue",15,"waiting for GitHub to close the issue","dn","n",null]]' ] \
    || fail "a pushed card whose issue is not closed yet, or one with no issue line that left the belt: $(after)"
  # GitHub still shows the issue open: the card stays on the belt with Push failed and the issue line's reason.
  jq -cn --arg c c5 --arg t "$(date -u +%FT%TZ)" '{card:$c,issue:5,step:"issue",time:$t,tokens:{claude:0,codex:0},result:"fail",sha:"",reason:"GitHub still shows the issue open 60 s after the push of x"}' >> "$S/cards.jsonl"
  echo "[$(issue 5 2026-01-01)]" > "$STUB/issues.json"; out=$(loop snapshot 2>/dev/null) || fail "snapshot after the issue mark exited non-zero"
  [ "$(after)" = '[["c5","issue",15,"GitHub did not close the issue","df","f","GitHub did not close the issue: GitHub still shows the issue open 60 s after the push of x"]]' ] \
    || fail "a card whose issue GitHub did not close left the belt, or its Push is not failed with the reason: $(after)"
  # Its last step in "Every step" says why, as Push does, and when, so the Board's red bar has both.
  [ "$(q '.belt[] | select(.card == "c5") | .track.records[-1] | [.name, .state, (.at != null), .why]')" \
    = '["GitHub did not close the issue","failed",true,"GitHub did not close the issue: GitHub still shows the issue open 60 s after the push of x"]' ] \
    || fail "a failed close of the issue has no time or reason in the card's steps: $(q '.belt[] | select(.card == "c5") | .track.records[-1]')"
  # The issue is closed later, by hand: the card leaves the belt, and in the landed list its Push is done, not failed
  # with "Issue still open"; every step stays recorded, the failed close of the issue among them.
  echo '[]' > "$STUB/issues.json"; out=$(loop snapshot 2>/dev/null) || fail "snapshot after the issue closed exited non-zero"
  [ "$(after)" = '[]' ] && [ "$(q '.landed[] | select(.card == "c5") | .track | [.detailAt, (.detail[14:16] | map(.state)), .steps[5].state, .reason]')" = '[null,["done","done"],"done",null]' ] \
    && [ "$(q '.landed[] | select(.card == "c5") | .track.records | map(select(.name | IN("pushed", "issue not closed")) | [.name, .state])')" = '[["pushed","done"],["issue not closed","failed"]]' ] \
    || fail "a card whose issue was closed by hand is still on the belt, or its Push is not done: $(after) $(q '.landed[] | select(.card == "c5") | .track')"
}
# With push off nothing pushes a landed card until the owner presses Push landed: it is off the belt, never "pushing"
# (the owner read that as a push against the rule), and listed as landed and not pushed, waiting. With push on, pushing.
t_snapshotpushoff() { latestart; cat "$STUB/late" >> "$S/cards.jsonl"; loop control rules push=off >/dev/null || fail "push=off failed"
  out=$(loop snapshot 2>/dev/null) || fail "snapshot with push off exited non-zero"
  [ "$(q '[(.belt | map(select(.landed)) | length), (.health.unpushed | map(.card)), (.landed[] | select(.card == "c5") | [.step, .pushed, .track.label, .track.at, .track.steps[5].state, (.track.records | map(.state) | index("now"))])]')" \
    = '[0,["c10","c5"],["landed",false,"Landed, waiting for Push landed",null,"todo",null]]' ] || fail "a landed card with push off is on the belt or pushing: $out"
  loop control rules push=on >/dev/null; out=$(loop snapshot 2>/dev/null) || fail "snapshot with push on exited non-zero"
  [ "$(after)" = '[["c10","push",14,"pushing","nt","n",null],["c5","push",14,"pushing","nt","n",null]]' ] || fail "with push on a landed card is not pushing: $(after)"
  # A Push landed that failed does not put them back on the belt with push off: the failure is the Control tab's.
  mark 5 push "${d}T00:40:00Z" fail "$ahead"; loop control rules push=off >/dev/null; out=$(loop snapshot 2>/dev/null) || fail "snapshot after a failed push exited non-zero"
  [ "$(q '[(.belt | map(select(.landed)) | length), (.health.pushError != null), (.landed[] | select(.card == "c5") | .track.label)]')" \
    = '[0,true,"Landed, waiting for Push landed"]' ] || fail "with push off a failed push puts a landed card back on the belt: $out"
}

# Bugs: a card that is building shows no dollars until its session ends, or $0 before the session has said
# anything; an answer of the model that comes as several events is counted once for each; a long session that is
# still producing output is reported stuck, or a silent one is not; a running test run does not say how many of its
# files are done; a review's findings are counted from the 1500 characters its record line keeps; the line written
# when a step ends is not what it was; a mark (when the issue was opened, each start, the follow-ups filed, the push,
# the issue closed or still open) is not recorded; a running review shows no tokens until it ends (its stream names
# none before then: they are in the session file Codex keeps, which is gone once the review ends).
# A card's run held at the build, the first review and the test run (t_live, the longest: conveyor.slowest starts it
# first): each case watches one, the holds before it open from the start (livestart <hold file>...).
livestart() {
  export TZ=UTC; setup "[$(issue 7 2026-01-01T00:00:00Z area:billing)]"; S=$ST
  seatset model claude-sonnet-5-5; seatset reviewer gpt-6.1-sol
  { for i in $(seq 40); do echo "[P2] a.txt:$i a finding long enough that forty of them pass the cut of the record line"; done
    printf '%s\n' '[P0] a.txt:99 the worst one, past the cut' 'b.txt:1 no mark here' '[P3] c.txt:1 small' 'NEW CARD: b.txt is stale' 'USER-VISIBLE: no' 'VERDICT: NO-GO'; } > "$STUB/review.1"
  for i in 2 3; do moved $i "$NOGO" > "$STUB/review.$i"; done
  # The session says nothing until $STUB/emit, then two answers (the first as two events with one id), then waits for $STUB/go.
  # Each hold of a stub here lasts until its file is there, however long that takes, or the stub folder is gone (the test's end).
  cat > "$STUB/claude" <<'EOF'
#!/usr/bin/env bash
cat > /dev/null; echo two >> a.txt
hold() { while [ -d "$STUB" ] && [ ! -e "$STUB/$1" ]; do sleep 0.1; done; }
a() { echo "{\"type\":\"assistant\",\"message\":{\"id\":\"$1\",\"usage\":{\"input_tokens\":1000000,\"cache_creation_input_tokens\":0,\"cache_read_input_tokens\":0,\"output_tokens\":0}}}"; }
hold emit; echo '{"type":"system","subtype":"init"}'; a m1; a m1; echo '{"type":"user"}'; a m2
echo '{"type":"assistant","message":{"id":"m2","content":[{"type":"tool_use","name":"Bash","input":{"command":"npm test"}}]}}'; hold go
echo '{"type":"result","is_error":false,"usage":{"input_tokens":10,"cache_creation_input_tokens":20,"cache_read_input_tokens":999,"output_tokens":5}}'
EOF
  # The first review opens its thread, Codex writes the running total to that thread's session file, and it waits for $STUB/go1.
  export CODEX_HOME=$STUB/codex-home; mkdir -p "$CODEX_HOME/sessions/2026/01/01"
  cat > "$STUB/review-cmd" <<'EOF'
if [ "$(wc -l < "$STUB/reviews")" = 1 ]; then
  echo '{"type":"thread.started","thread_id":"0aa1-b2"}'; echo '{"type":"turn.started"}'
  f=$CODEX_HOME/sessions/2026/01/01/rollout-2026-01-01T00-00-00-0aa1-b2.jsonl
  echo '{"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":500000,"cached_input_tokens":0,"output_tokens":0}}}}' > "$f"
  echo '{"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1000000,"cached_input_tokens":400000,"output_tokens":500}}}}' >> "$f"
  while [ -d "$STUB" ] && [ ! -e "$STUB/go1" ]; do sleep 0.1; done
fi
EOF
  # The test run is the default runner's: nothing of a file in its own output but the web half's count; each half
  # writes its lines to a log of its own in the folder CONVEYOR_TEST_LOG names, the web half's in vitest's colours.
  # A log of this worktree written anywhere else (where the runner once wrote) is not this run's.
  export TMPDIR=$STUB/tmp; mkdir -p "$TMPDIR/conveyor"
  cat > "$STUB/test-cmd" <<'EOF'
L=$CONVEYOR_TEST_LOG
printf 'TESTRUN files=7 root=%s\n-- ok   other.test.ts 0s\n' "$PWD" > "$TMPDIR/conveyor/test-changed-other.log"
echo "test-changed: 3 root test file(s) selected from 2 changed file(s)"; echo "test-changed: 2 web test file(s) selected"
printf 'TESTRUN files=3 root=%s\n...\n-- ok   a.test.ts 0s\n' "$PWD" > "$L/test-changed-new.log"
printf 'TESTRUN files=? root=%s\n\n \033[32m\342\234\223\033[39m e2e/x.test.ts \033[2m(\033[22m\033[2m3 tests\033[22m\033[2m)\033[22m\033[32m 5\033[2mms\033[22m\033[39m\n' "$PWD" > "$L/test-changed-web-new.log"
while [ -d "$STUB" ] && [ ! -e "$STUB/go2" ]; do sleep 0.1; done; echo "-- FAIL b.test.ts 0s" >> "$L/test-changed-new.log"
EOF
  snap() { loop snapshot 2>/dev/null | jq -c "$1"; }
  # A snapshot is taken again only once the card's records, live record or review session file changed (one every 0.2 s
  # was the case's longest part); the one that showed <want> is kept ($SEEN) for the checks of the run held there (seen).
  until_is() { local was='' now; while :; do # <jq filter> <want>
    now=$(cat "$S/cards.jsonl" "$T/$CASE/cards"/*.live "$CODEX_HOME"/sessions/*/*/*/*.jsonl 2>/dev/null | cksum)
    if [ "$now" != "$was" ]; then was=$now; SEEN=$(loop snapshot 2>/dev/null); [ "$(seen "$1")" != "$2" ] || return 0; fi
    kill -0 "$run" 2>/dev/null || fail "never $2 before the run ended: $1 is $(snap "$1")"; sleep 0.1
  done; }; seen() { jq -c "$1" <<<"$SEEN"; }
  local h; for h; do : > "$STUB/$h"; done; loop run >/dev/null 2>&1 & run=$!
}
t_livebuild() { livestart
  until_is '.belt[0].track.label' '"building"'
  [ "$(seen '.belt[0] | [.usd, .reading, .tokens.claude, .live.lastOutputAt, .track.detailAt, .track.at]')" = '[null,false,0,null,5,0]' ] || fail "a session that has said nothing: $(seen '.belt[0]')"
  # Health asks 4 s on (the clock seam, CONVEYOR_NOW), never after a pause: the session, silent since its start, is then past the limit.
  at=$(( $(date +%s) + 4 ))
  [ "$(CONVEYOR_NOW=$at tuned '.tunables.stuck = 3' loop health | jq -c '.stuck | map([.issue, .step])')" = '[[7,"build"]]' ] || fail "a session silent past the limit is not stuck: $(CONVEYOR_NOW=$at tuned '.tunables.stuck = 3' loop health)"
  : > "$STUB/emit"; until_is '.belt[0].usd' 4
  # Health asks at a second past the last output (the clock seam), not whenever a loaded machine gets to it: the
  # start is then over 3 s old, so a health that ignored the output would say stuck.
  at=$(( $(seen '.belt[0].live.lastOutputAt | fromdate') + 1 ))
  [ "$(CONVEYOR_NOW=$at tuned '.tunables.stuck = 3' loop health | jq -c '.stuck')" = '[]' ] || fail "a session whose start is old and whose last output is new is stuck: $(CONVEYOR_NOW=$at tuned '.tunables.stuck = 3' loop health)"
  [ "$(seen '.belt[0] | [.reading, .tokens.claude, .live.turns, (.live.lastOutputAt | fromdate > 0), .step]')" = '[true,2000000,2,true,"build"]' ] || fail "the reading of a running session: $(seen '.belt[0]')"
  until_is '.belt[0].live.action' '"Bash: npm test"'
  [ "$(seen '.cost.today')" = 0 ] || fail "a running step is in the dollars of the steps that ended: $(seen .cost)"
  kill $run; wait $run; : # the run is held here: what it would do next is the next case's
}
# The first review says NO-GO (44 lines, 43 of them findings), the fix session runs straight through, the next two say NO-GO too.
t_livereview() { livestart emit go
  until_is '.belt[0] | [.track.label, .tokens.codex]' '["review 1 of 3",600500]'
  [ "$(seen '.belt[0] | [.reading, .tokens.claude, .usd > 0, (.live.lastOutputAt | fromdate > 0)]')" = '[true,35,true,true]' ] || fail "the reading of a running review: $(seen '.belt[0]')"
  kill $run; wait $run; : # the run is held here: what it would do next is the next case's
}
t_live() { livestart emit go go1
  until_is '.belt[0].track.files' '{"run":2,"of":5}'
  [ -z "$(find "$CODEX_HOME/sessions" -type f)" ] || fail "the session file of a review that ended is left: $(find "$CODEX_HOME/sessions" -type f)"
  [ "$(seen '.belt[0] | [.track.label, .track.detailAt, (.reviews | map([.round, .verdict, .fixed, (.counts | tojson)]))]')" \
    = '["tests",11,[[1,"NO-GO",true,"{\"P0\":1,\"P1\":1,\"P2\":40,\"P3\":1}"],[2,"NO-GO",true,"{\"P0\":0,\"P1\":1,\"P2\":0,\"P3\":0}"],[3,"NO-GO",false,"{\"P0\":0,\"P1\":1,\"P2\":0,\"P3\":0}"]]]' ] \
    || fail "the reviews in order, or the step of a running test run: $(seen '.belt[0] | [.track.label, .reviews]')"
  echo OPEN > "$STUB/state"; : > "$STUB/go2"; wait "$run" || fail "run exited non-zero"
  [ "$(st 'select(.step == "review") | [(.reason | length), .counts.P2] | tojson' | head -n 1)" = '[1500,40]' ] || fail "counts not taken from the whole review: $(st 'select(.step == "review") | .counts')"
  [ "$(st 'select(.step == "build") | [.tokens.claude, (.usage | map(tostring) | join(" "))] | tojson')" = '[35,"10 20 0 999 5"]' ] || fail "the line written when the session ends changed: $(st 'select(.step == "build")')"
  [ "$(st '[.step, .of // .created // (.followups | arrays | tojson) // .result] | join(":")' | tr '\n' ' ')" \
    = 'picked:2026-01-01T00:00:00Z worktree:ok deps:ok brief:ok start:build build:ok start:review review:NO-GO start:fix fix:ok start:review review:NO-GO start:fix fix:ok start:review review:NO-GO start:test test:pass start:file filed:[100101] start:land landed:[100101] pushed:ok issue:fail ' ] \
    || fail "the marks of a card: $(st '[.step, .of // .created // (.followups | arrays | tojson) // .result] | join(":")' | tr '\n' ' ')"
  [ -z "$(ls "$T/$CASE/cards")" ] || fail "a live record or a worktree is left: $(ls "$T/$CASE/cards")"
  # GitHub kept the issue open, so the card is still at Push, failed: its detail is at "issue closed".
  [ "$(snap '.landed[0] | [(.rounds | length), .reviews, (.track.detail | map(.state) | join(" ")), .track.detail[16].n, .track.detail[0].sec > 86400, .track.detailAt, .track.at, .track.steps[5].state]')" \
    = '[3,3,"done done done done done done done done done done done done skipped done done failed done",1,true,15,5,"failed"]' ] || fail "the landed card's reviews and track: $(snap '.landed[0]')"
}

# Bugs: the track of a card on the belt names the wrong step, hides a fix round the card did not need instead
# of showing it skipped, loses a failed test run or a rebuild after a landing conflict, or differs in shape from card
# to card; a review recorded before findings were counted shows zeros.
# Bugs: the track is 17 small chips, and a card being pushed has none of them marked; Push does not follow
# Land; a step skipped (Fix after a GO, Build of a card landed from a kept patch) reads as to come; a time is estimated
# from past cards; a card resumed from a kept patch does not count the time of the card whose work it resumes. The 17
# steps are still the detail a card opens to.
t_track() {
  export TZ=UTC; setup '[]'; S=$ST; mkdir -p "$S"; d=$(date -u +%F); local made; made=$(date -u -d "$d 1 hour ago" +%FT%TZ)
  card() { # <issue> <step[:result[:extra json]]>...: its lines a minute apart; b, r, f, t, F, l and x are the starts of build, review, fix, test, the filing of follow-ups, land and rebase, and - a minute with no line
    local n=$1 m=0 a step res x; shift; for a; do IFS=: read -r step res x <<<"$a"
      case $step in -) m=$((m + 1)); continue ;; b) step=start; x='{"of":"build"}' ;; r) step=start; x='{"of":"review"}' ;; f) step=start; x='{"of":"fix"}' ;; t) step=start; x='{"of":"test"}' ;;
        l) step=start; x='{"of":"land"}' ;; F) step=start; x='{"of":"file"}' ;; x) step=start; x='{"of":"rebase"}' ;; picked) x="{\"title\":\"T$n\",\"created\":\"$made\"}" ;; esac
      printf '%s\t%sT00:%02d:00Z\t%s\t%s\n' "$step" "$d" "$m" "${res:-ok}" "${x:-{\}}"; m=$((m + 1))
    done | jq -cR --arg c "c$n" --argjson i "$n" 'split("\t") as [$s, $t, $r, $x]
      | {card:$c,issue:$i,step:$s,time:$t,tokens:{claude:0,codex:0},result:$r,sha:"",reason:""} * ($x | fromjson)' >> "$S/cards.jsonl"
  }
  K='{"counts":{"P0":0,"P1":1,"P2":2,"P3":0}}'; Z='{"counts":{"P0":0,"P1":0,"P2":0,"P3":0}}'; pre="picked worktree deps brief b build r"
  for n in 1 2 3; do card $n $pre "review:GO:$Z" t test:pass l 'landed:ok:{"sha":"abc","product":false}' pushed issue; done
  card 4 $pre "review:NO-GO:$K" f fix r "review:GO:$Z" t test:pass l 'landed:ok:{"sha":"abc","product":false}' pushed issue
  card 20 picked
  card 21 picked worktree deps
  card 22 picked worktree deps brief b
  card 23 $pre "review:NO-GO:$K" f
  card 24 $pre "review:GO:$Z" t
  card 25 $pre "review:GO:$Z" t test:fail f
  card 26 $pre "review:GO:$Z" t test:pass l x
  card 27 $pre "review:NO-GO:$K" f fix r review:NO-GO f fix r "review:NO-GO:$K" t test:pass F 'filed:ok:{"followups":[100101,100102]}' l
  card 28 $pre "review:GO:$Z" t test:pass l x rebase r
  # The follow-ups are being filed (GitHub is asked once for each): that is the step in progress, not the landing, and
  # the landing before it in the track is still to come, not skipped. After a rebuild it is the same step. Of the six
  # steps the filing is Land's, which it comes before, so the track never steps back from Push to Land.
  card 29 $pre "review:NO-GO:$K" f fix r review:NO-GO f fix r "review:NO-GO:$K" t test:pass F
  card 30 $pre "review:GO:$Z" t test:pass l x rebase r "review:NO-GO:$K" t test:pass F
  # Bug: the rebuild had no step of its own. A landing that has only begun may yet meet a conflict: the
  # rebuild is still to come there, and skipped only on a card that landed without one.
  card 31 $pre "review:GO:$Z" t test:pass l
  # Tests that fail twice, each time fixed and reviewed again: "Every step" lists each run, fix and review with its own
  # seconds, not summed into one slot.
  # A failed run keeps its reason, which the Board shows on the red bar.
  card 32 $pre "review:GO:$Z" t 'test:fail:{"reason":"exit 124: timeout"}' f fix r "review:GO:$Z" t test:fail f fix r "review:GO:$Z" t test:pass l
  # A review that failed keeps its reason too: without it the red bar repeats its name.
  card 33 $pre 'review:fail:{"reason":"review process exited 124"}' r
  # A fix keeps the reason its line names (what started it), which the Board labels it by; one with none has none.
  card 34 picked worktree deps brief b build f 'fix:ok:{"reason":"the Done-when check failed: D1 not met"}' r "review:NO-GO:$K" f fix r
  # Issue 650: a fix the Done-when check on the build's reply started is Build's, not a Fix round before the first
  # review: running (36), then done (35); a fix after a NO-GO review is still Fix (37).
  W='build:ok:{"doneWhen":{"items":1,"met":0,"failed":["D1"]}}'
  card 35 picked worktree deps brief b "$W" f 'fix:ok:{"reason":"the Done-when check failed: D1"}' r
  card 36 picked worktree deps brief b "$W" f
  card 37 $pre "review:NO-GO:$K" f fix r
  # A fifth lands, after a fix round that took 3 minutes.
  card 5 $pre "review:NO-GO:$K" f - - fix r "review:GO:$Z" t test:pass l 'landed:ok:{"sha":"abd","product":false}'
  # Five cards land after a rebuild (two minutes each): no time of any step is estimated from them.
  for n in 6 7 8 9 10; do card $n $pre "review:GO:$Z" t test:pass l x - rebase r - - "review:GO:$Z" t test:pass l 'landed:ok:{"sha":"abe","product":false}'; done
  # Bug: a build, fix, rebuild or landing that fails takes the card off the belt, and the blocked list had no
  # track: no view showed the step that failed or how long it ran. Each blocked card carries its track, the step it
  # stopped in failed with its seconds; one waiting for the yes of the owner failed nothing.
  card 40 picked worktree deps brief b - - 'blocked:blocked:{"reason":"build: session failed (exit 124)"}'
  card 41 $pre "review:NO-GO:$K" f - 'blocked:blocked:{"reason":"fix: session failed"}'
  card 42 $pre "review:GO:$Z" t test:pass l - - - 'blocked:blocked:{"reason":"main moved during the landing; nothing was landed"}'
  card 43 $pre "review:GO:$Z" t test:pass l x - 'blocked:blocked:{"reason":"rebase: session failed"}'
  card 44 picked - "blocked:blocked:{\"reason\":\"worktree: the engine could not link the dependencies of the main checkout: no\"}"
  card 45 $pre "review:GO:$Z" "blocked:blocked:{\"reason\":\"visible to customers or staff: needs Dana's yes: a new line\"}"
  card 46 $pre - 'blocked:blocked:{"reason":"review 1: review failed (exit 124)"}'
  card 47 picked worktree deps 'blocked:blocked:{"reason":"brief: gh issue view failed"}'
  # A card resumed from the kept patch of a blocked card counts that card's time, shows its first start and gives that card's steps (earlier, #545):
  # card 60 ran 7 minutes and was blocked; card 61 took its patch up and landed 11 minutes after its own pick-up.
  card 60 picked worktree deps brief b - - 'blocked:blocked:{"reason":"build: session failed (exit 1)"}'
  card 61 picked 'worktree:ok:{"reason":"resumed from the kept patch of card c60: one session, then review"}' deps brief b build r "review:GO:$Z" t test:pass l 'landed:ok:{"sha":"abg","product":false}'
  card 62 picked worktree deps brief b build r
  # One snapshot of the cards above, and one jq a card: one after each group and one a line took the case 6 s more.
  out=$(loop snapshot) || fail "snapshot exited non-zero"
  [ "$(jq -c '.belt[] | select(.card == "c34") | .track.records[6:9] | map([.name, .reason])' <<<"$out")" \
    = '[["fix 1","the Done-when check failed: D1 not met"],["review 1 (NO-GO)",null],["fix 2",null]]' ] \
    || fail "a fix lost the reason that started it: $(jq -c '.belt[] | select(.card == "c34") | .track.records' <<<"$out")"
  [ "$(jq -c '.belt[] | select(.card == "c33") | .track.records[6] | [.name, .state, .why]' <<<"$out")" = '["review 1 (fail)","failed","review process exited 124"]' ] \
    || fail "a failed review lost its reason: $(jq -c '.belt[] | select(.card == "c33") | .track.records' <<<"$out")"
  [ "$(jq -c '.belt[] | select(.card == "c32") | .track.records[6:] | map([.name, .state, .sec, .why])' <<<"$out")" \
    = '[["review 1 (GO)","done",60,null],["tests failed","failed",60,"exit 124: timeout"],["fix 1","done",60,null],["review 2 (GO)","done",60,null],["tests failed","failed",60,null],["fix 2","done",60,null],["review 3 (GO)","done",60,null],["tests passed","done",60,null],["landing","now",null,null]]' ] \
    || fail "every step of a card whose tests failed twice: $(jq -c '.belt[] | select(.card == "c32") | .track.records' <<<"$out")"
  b() { jq -c --arg c "c$1" ".belt[] | select(.card == \$c) | $2" <<<"$out"; }
  marks() { b "$1" '.track | [.detailAt, .label, (.detail | map({done: "+", now: ">", skipped: "-", failed: "!", todo: "."}[.state]) | join(""))]'; }
  # The six steps Build, Review, Fix, Test, Land, Push: the step in progress, each step's mark, and the rounds of Review and Fix.
  six() { b "$1" '.track | [.at, (.steps | map({done: "+", now: ">", skipped: "-", failed: "!", todo: "."}[.state]) | join("")), .steps[1].n, .steps[2].n]'; }
  [ "$(jq -c '[.belt[].track.detail | map(.name)] | unique' <<<"$out")" = '[["queued","picked","worktree ready","dependencies linked","brief written","building","review 1","fix 1","review 2","fix 2","review 3","tests","rebuild","landing","pushed","issue closed","follow-ups filed"]]' ] \
    || fail "the track is not the same 17 steps on every card: $(jq -c '[.belt[].track.detail | map(.name)] | unique' <<<"$out")"
  while read -r n want; do [ "$(marks "$n")" = "$want" ] || fail "track of card $n: $(marks "$n"), not $want"; done <<'EOF'
20 [2,"making the worktree","++>.............."]
21 [4,"writing the brief","++++>............"]
22 [5,"building","+++++>..........."]
23 [7,"fix after review 1","+++++++>........."]
24 [11,"tests","+++++++---->....."]
25 [11,"fix after failed tests","+++++++----!....."]
26 [12,"rebuilding after a conflict","+++++++----+>...."]
27 [13,"landing","++++++++++++.>..+"]
28 [13,"review 2 after the rebuild","+++++++----++>..."]
29 [16,"filing follow-ups","++++++++++++....>"]
30 [16,"filing follow-ups","+++++++----++...>"]
31 [13,"landing","+++++++----+.>..."]
EOF
  [ "$(jq -c '[.belt[].track.steps | map(.name)] | unique' <<<"$out")" = '[["Build","Review","Fix","Test","Land","Push"]]' ] \
    || fail "the track is not the six steps in order: $(jq -c '[.belt[].track.steps | map(.name)] | unique' <<<"$out")"
  while read -r n want; do [ "$(six "$n")" = "$want" ] || fail "six steps of card $n: $(six "$n"), not $want"; done <<'EOF'
20 [0,">.....",0,0]
21 [0,">.....",0,0]
22 [0,">.....",0,0]
23 [2,"++>...",1,1]
24 [3,"++->..",1,0]
25 [2,"++>...",1,1]
26 [4,"++-+>.",1,0]
27 [4,"++++>.",3,2]
28 [1,"+>-+..",2,0]
29 [4,"++++>.",3,2]
30 [4,"++-+>.",2,0]
31 [4,"++-+>.",1,0]
34 [1,"+>+...",2,1]
35 [1,"+>....",1,0]
36 [0,">.....",0,0]
37 [1,"+>+...",2,1]
EOF
  # The note /units and the Board draw on Build for a reply-check fix: running, done, and none without one.
  [ "$(jq -c '[.belt[] | select(.card | IN("c34", "c35", "c36", "c37")) | [.card, .track.steps[0].replyFix]] | sort' <<<"$out")" = '[["c34","done"],["c35","done"],["c36","now"],["c37",null]]' ] \
    || fail "the reply-check fix on Build: $(jq -c '[.belt[] | select(.card | IN("c34", "c35", "c36", "c37")) | [.card, .track.steps[0]]]' <<<"$out")"
  # Build is the set-up and the build, never the hour the issue sat queued; a failed test run is run again after its
  # fix (to come, not failed); a rebuild and the landing it follows are both Land's; the follow-ups filed are named on Push.
  [ "$(b 22 '.track.steps[0].sec')" = 180 ] && [ "$(b 25 '.track.steps[3] | [.state, .sec] | tojson')" = '"[\"todo\",60]"' ] \
    && [ "$(b 26 '.track.steps[4].sec')" = 60 ] && [ "$(b 27 '[.track.steps[5].followups, .track.steps[1].of] | tojson')" = '"[2,3]"' ] \
    || fail "the seconds of the six steps: $(b 22 .track.steps) $(b 25 .track.steps) $(b 26 .track.steps) $(b 27 .track.steps)"
  [ "$(b 27 '[.track.detail[16].n, (.reviews | map([.round, .verdict, .fixed, .counts.P2]))] | tojson')" = '"[2,[[1,\"NO-GO\",true,2],[2,\"NO-GO\",true,null],[3,\"NO-GO\",false,2]]]"' ] \
    || fail "three reviews, one of them recorded with no counts: $(b 27 .reviews)"
  [ "$(b 22 '[.reviews, .track.detail[0].sec, .track.detail[2].sec, .track.since[14:16]] | tojson')" = '"[[],3600,60,\"04\"]"' ] || fail "no review yet, the time queued, a step's seconds or when the step began: $(b 22 .)"
  [ "$(b 25 '.track.detail[11].sec')" = 60 ] || fail "the seconds of a failed test run: $(b 25 .track.detail[11])"
  # The rebuild's seconds are its session's alone; the landing that met the conflict keeps its own.
  [ "$(b 28 '.track.detail[12:14] | map([.name, .state, .sec]) | tojson')" = '"[[\"rebuild\",\"done\",60],[\"landing\",\"now\",60]]"' ] || fail "the seconds of a rebuild, apart from the landing's: $(b 28 '.track.detail[12:14]')"
  [ "$(jq -c '.landed | map(select(.card == "c1" or .card == "c5") | [.card, (.rounds | map(.verdict) | join(" ")), (.track.detail[7:11] + .track.detail[12:13] + .track.detail[14:] | map(.state[0:1]) | join(""))]) | sort | .[]' <<<"$out" | tr '\n' ' ')" \
    = '["c1","GO","sssssdds"] ["c5","NO-GO GO","ddssstts"] ' ] || fail "a landed card's reviews and the end of its track: $(jq -c '.landed | map([.card, .rounds, .track.detail])' <<<"$out")"
  # Landed: Fix skipped after a GO; Push done once the push and the close of the issue are recorded, to come before.
  [ "$(jq -c '.landed | map(select(.card == "c1" or .card == "c5") | [.card, .track.at, (.track.steps | map(.state[0:1]) | join(""))]) | sort' <<<"$out")" = '[["c1",null,"ddsddd"],["c5",null,"dddddt"]]' ] \
    || fail "the six steps of a landed card: $(jq -c '.landed | map([.card, .track.steps])' <<<"$out")"
  # The marks have their seconds too: the follow-ups took a minute to file, the push came a minute after the landing
  # and the issue closed a minute after the push.
  [ "$(b 27 '.track.detail[16] | [.sec, .n] | tojson')" = '"[60,2]"' ] || fail "the seconds of the follow-ups filed: $(b 27 .track.detail[16])"
  [ "$(jq -c '.landed[] | select(.card == "c1") | .track.detail[14:16] | map(.sec)' <<<"$out")" = '[60,60]' ] \
    || fail "the seconds of the push and of the issue closed: $(jq -c '.landed[] | select(.card == "c1") | .track.detail[14:16]' <<<"$out")"
  [ "$(jq -c '.landed[] | select(.card == "c6") | .track.detail[12:14] | map([.state, .sec])' <<<"$out")" = '[["done",120],["done",360]]' ] \
    || fail "a landed card that was rebuilt lost the rebuild's own time: $(jq -c '.landed[] | select(.card == "c6") | .track.detail[12:14]' <<<"$out")"
  # Bug: its landSec counted only the landing that landed, not the minute of the one that met the conflict.
  [ "$(jq -c '.landed[] | select(.card == "c6") | .metrics | [.landSec, .rebuildSec]' <<<"$out")" = '[120,120]' ] \
    || fail "a rebuilt card's landSec lost the landing that met the conflict: $(jq -c '.landed[] | select(.card == "c6") | .metrics' <<<"$out")"
  [ "$(jq -c '.belt | map(select(.issue >= 40 and .issue <= 47)) | length' <<<"$out")" = 0 ] || fail "a blocked card is on the belt"
  nd() { jq -c --arg c "c$1" '.needsYou | .waiting[], .blocked[] | select(.card == $c) | [(.track.detail | map({done: "+", now: ">", skipped: "-", failed: "!", todo: "."}[.state]) | join("")), (.track.detail | map(select(.state == "failed") | [.name, .sec]))]' <<<"$out"; }
  while read -r n want; do [ "$(nd "$n")" = "$want" ] || fail "track of blocked card $n: $(nd "$n"), not $want"; done <<'EOF'
40 ["+++++!...........",[["building",180]]]
41 ["+++++++!.........",[["fix 1",120]]]
42 ["+++++++----+.!...",[["landing",240]]]
43 ["+++++++----+!....",[["rebuild",120]]]
44 ["+++!.............",[["dependencies linked",120]]]
45 ["+++++++..........",[]]
46 ["++++++!..........",[["review 1",120]]]
47 ["++++!............",[["brief written",60]]]
EOF
  nd6() { jq -c --arg c "c$1" '.needsYou | .waiting[], .blocked[] | select(.card == $c) | .track | [.at, (.steps | map({done: "+", now: ">", skipped: "-", failed: "!", todo: "."}[.state]) | join(""))]' <<<"$out"; }
  while read -r n want; do [ "$(nd6 "$n")" = "$want" ] || fail "six steps of blocked card $n: $(nd6 "$n"), not $want"; done <<'EOF'
40 [null,"!....."]
41 [null,"++!..."]
42 [null,"++-+!."]
43 [null,"++-+!."]
44 [null,"!....."]
45 [null,"++...."]
46 [null,"+!...."]
47 [null,"!....."]
EOF
  [ "$(jq -c '.needsYou.blocked[] | select(.card == "c41") | .reviews | map([.round, .verdict, .fixed])' <<<"$out")" = '[[1,"NO-GO",true]]' ] || fail "a blocked card's reviews: $(jq -c '.needsYou.blocked[] | select(.card == "c41") | .reviews' <<<"$out")"
  [ "$(jq -c '.landed[] | select(.card == "c61") | [.start[11:16], .pickedAt[11:16], .priorSec, .totalSec, (.earlier | map([.card, .sec, .reason, .track.steps[0].state]))]' <<<"$out")" = '["00:00","00:00",420,1080,[["c60",420,"build: session failed (exit 1)","failed"]]]' ] \
    && [ "$(jq -c '.belt[] | select(.card == "c62") | [.start, .pickedAt, .priorSec, .totalSec, .earlier] | [.[0] == .[1], .[2], .[3], .[4]]' <<<"$out")" = '[true,0,null,[]]' ] \
    || fail "start and overall time: $(jq -c '[.landed[], .belt[]] | map(select(.card == "c61" or .card == "c62") | {card, start, pickedAt, priorSec, totalSec, earlier})' <<<"$out")"
}

# Bug: a card that landed, was then blocked by a loop restart ("its process ended without a result"), and still
# pushed and had its issue closed stays in Needs you as blocked, in the snapshot and in health (the host's view of the
# loop's problems): a done card shown as needing the owner. A card blocked after it landed with no later step of its
# own is still blocked. Record order decides, not time: c16's push started before its block and is written after it.
t_unblock() {
  export TZ=UTC; setup '[]'; S=$ST; mkdir -p "$S"; d=$(date -u +%F)
  echo x > "$R/n.txt"; git -C "$R" add -A; git -C "$R" commit -qm next; sha=$(git -C "$R" rev-parse HEAD); git -C "$R" push -q origin main
  rec() { # <card> <issue> <minute> <step> <result> [extra json]
    jq -cn --arg c "$1" --argjson i "$2" --arg t "${d}T00:$3:00Z" --arg s "$4" --arg r "$5" --argjson x "${6:-{\}}" \
      '{card:$c,issue:$i,step:$s,time:$t,tokens:{claude:0,codex:0},result:$r,sha:"",reason:""} * $x' >> "$S/cards.jsonl"
  }
  for c in c14:14 c15:15 c16:16; do rec "${c%:*}" "${c#*:}" 00 picked ok '{"title":"T"}'; rec "${c%:*}" "${c#*:}" 01 review GO; done
  rec c14 14 02 landed ok "{\"sha\":\"$sha\",\"product\":false}"
  rec c14 14 03 blocked blocked '{"reason":"its process ended without a result"}'
  rec c14 14 04 pushed ok "{\"sha\":\"$sha\",\"sec\":1,\"head\":\"$sha\"}"; rec c14 14 05 issue ok
  rec c15 15 02 landed ok "{\"sha\":\"$sha\",\"product\":false}"
  rec c15 15 03 blocked blocked '{"reason":"its process ended without a result"}'
  rec c16 16 02 landed ok "{\"sha\":\"$sha\",\"product\":false}"
  rec c16 16 05 blocked blocked '{"reason":"its process ended without a result"}'
  rec c16 16 04 pushed ok "{\"sha\":\"$sha\",\"sec\":1,\"head\":\"$sha\"}"
  out=$(loop snapshot) || fail "snapshot exited non-zero"
  [ "$(jq -c '[.needsYou.blocked[].card]' <<<"$out")" = '["c15"]' ] \
    || fail "a card that pushed after it was blocked is in Needs you, or one blocked after it landed is not: $(jq -c '.needsYou.blocked' <<<"$out")"
  [ "$(jq -c '[.landed[] | select(.card == "c14" or .card == "c16") | [.step, .pushed]]' <<<"$out")" = '[["landed",true],["landed",true]]' ] \
    || fail "the card that pushed after it was blocked does not show as landed and pushed: $(jq -c '.landed' <<<"$out")"
  [ "$(jq -c '[.health.blocked[].card]' <<<"$out")" = '["c15"]' ] && [ "$(loop health | jq -c '[.blocked[].card]')" = '["c15"]' ] \
    || fail "health lists the card that pushed after it was blocked: $(loop health | jq -c .blocked)"
}

# Bug: every snapshot waits for the records' lock. On a busy host the loop's cards hold that lock for seconds at a
# time (a card waiting on a same-file card asks under it at every poll), so the wait was 3 to 7 s of a 20 to 40 s
# snapshot, and every reader of it timed out. Or, not waiting for it, the snapshot no longer holds a new issue before
# its copy, no longer dates the issues it lists, or reads a card `retry` moved from both files.
t_snaplock() {
  setup "[$(issue 5 2026-03-01 P2)]"
  # Every flock on the card records is noted: the stub stands before the real one, which it then runs.
  real=$(command -v flock)
  # And the snapshot the retry below sets off says, when it comes to the lock of its copy, that it has to wait for it.
  { printf '#!/usr/bin/env bash\nreal=%q\n' "$real"; cat <<'EOF'; } > "$STUB/flock"; chmod +x "$STUB/flock"
[ ! /dev/fd/9 -ef "$ST/cards.jsonl" ] || echo "$*" >> "$STUB/locks"
if [ -e "$STUB/racing" ] && [ /dev/fd/5 -ef "$ST/cards.jsonl.checked.lock" ]; then rm -f "$STUB/racing"; "$real" -n 5 || echo waits > "$STUB/race"; fi
exec "$real" "$@"
EOF
  loop control start held >/dev/null 2>&1 || fail "start held was refused"
  jq -c ". + [$(issue 6 2026-03-02 P2)]" "$STUB/issues.json" > "$STUB/i" && mv "$STUB/i" "$STUB/issues.json"
  on() { local t=$1; shift; CONVEYOR_NOW=$(date -u -d "$t" +%s) loop "$@"; }
  # A new issue to hold is the one thing a snapshot takes the lock for, once: #6, new under Held, is held before the copy.
  : > "$STUB/locks"; out=$(on 2026-10-01 snapshot) || fail "snapshot exited non-zero"
  [ "$(wc -l < "$STUB/locks")" -eq 1 ] || fail "the snapshot that holds a new issue took the records' lock $(wc -l < "$STUB/locks") times, not once: $(tr '\n' ' ' < "$STUB/locks")"
  [ "$(jq -c '[.control.held, (.queue.order | map(.issue)), (.queue.holding | map(.issue)), ([.queue.order[], .queue.holding[]] | all(.since != null))]' <<<"$out")" = '[[6],[5],[6],true]' ] \
    || fail "the snapshot does not hold the new issue and date both: $(jq -c '[.control.held, .queue]' <<<"$out")"
  # A hold dates its issue in moved.json under that file's own lock, and the next snapshot shows that time.
  on 2026-11-01 control hold 5 >/dev/null 2>&1 || fail "control hold was refused"
  # With no new issue to hold, the snapshot never waits for the lock.
  : > "$STUB/locks"; out=$(on 2026-11-05 snapshot) || fail "snapshot exited non-zero"
  [ ! -s "$STUB/locks" ] || fail "a snapshot with no new issue to hold took the records' lock: $(tr '\n' ' ' < "$STUB/locks")"
  [ "$(jq -c '.queue.holding | map([.issue, .since])' <<<"$out")" = '[[5,"2026-11-01T00:00:00Z"],[6,"2026-10-01T00:00:00Z"]]' ] \
    || fail "a hold's time is not the snapshot's since: $(jq -c .queue.holding <<<"$out")"
  # A snapshot that begins while `retry` has a card's lines in both files (appended to the retried file, the records
  # not yet rewritten) waits for the rewrite: the stub of python3 starts one when the state helper is asked to rewrite
  # the records, and lets the rewrite go on only when the snapshot waits for the lock of its copy (waits) or has ended
  # without waiting (done).
  line() { printf '{"card":"c1","issue":5,"step":"%s","time":"%s","tokens":{"claude":0,"codex":0},"result":"%s","sha":"","reason":"%s","repo":"r"}\n' "$@"; }
  line picked 2026-11-06T00:00:00Z ok '' >> "$ST/cards.jsonl"; line blocked 2026-11-06T00:10:00Z blocked 'build: failed' >> "$ST/cards.jsonl"
  { printf '#!/usr/bin/env bash\nreal=%q; snap() { CONVEYOR_MAIN=%q CONVEYOR_CARDS=%q bash %q snapshot; }\n' "$(command -v python3)" "$R" "$T/$CASE/cards" "$SRC/conveyor.sh"; cat <<'EOF'; } > "$STUB/python3"; chmod +x "$STUB/python3"
if [[ " $* " == *' rewrite cards '* ]] && [ -p "$STUB/race" ]; then
  : > "$STUB/racing"; ( snap > "$STUB/mid" 2>/dev/null; echo done > "$STUB/race" ) 5>&- 9>&- > /dev/null &
  read -r w < "$STUB/race"; echo "$w" > "$STUB/raced"
fi
exec "$real" "$@"
EOF
  mkfifo "$STUB/race"; loop retry 5 >/dev/null 2>&1 || fail "retry was refused"
  [ "$(cat "$STUB/raced" 2>/dev/null)" = waits ] || fail "a snapshot begun while retry had the card's lines in both files did not wait for the rewrite: it shows $(jq -c '[(.needsYou.blocked | map(.card)), .metrics.prev.cards]' "$STUB/mid" 2>/dev/null)"
  read -r x < "$STUB/race"; rm -f "$STUB/race" "$STUB/python3"
  # What it then shows is the card after the retry: moved, once, and no longer waiting on the owner.
  [ "$(jq -c '[.needsYou.blocked, .metrics.prev.cards]' "$STUB/mid")" = '[[],1]' ] || fail "the snapshot that waited does not show the retried card moved, once: $(jq -c '[.needsYou.blocked, .metrics.prev.cards]' "$STUB/mid")"
}
