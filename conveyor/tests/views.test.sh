#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: the snapshot. The live cost is viewslive.test.sh's, the track viewstrack.test.sh's.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

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
  card() { # <issue> <day> <step[:result[:extra json]]>...: one jq for the card's lines, not one a line
    local n=$1 day=$2 m=0 a step res x; shift 2
    for a; do
      IFS=: read -r step res x <<<"$a"
      case $step in picked) x="{\"title\":\"T$n\"}" ;; build|fix) x=${x:-$B} ;; review) x=${x:-$V} ;; test) x='{"sec":60,"usage":{"input":0,"write":0,"write1h":0,"read":0,"output":0}}' ;; esac
      printf '%s\t%sT00:%02d:00Z\t%s\t%s\n' "$step" "$day" "$m" "${res:-ok}" "${x:-{\}}"; m=$((m + 1))
    done | jq -cR --arg c "c$n" --argjson i "$n" 'split("\t") as [$s, $t, $r, $x]
      | {card:$c,issue:$i,step:$s,time:$t,tokens:{claude:0,codex:0},result:$r,sha:"",reason:""} * ($x | fromjson)' >> "$S/cards.jsonl"
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
  out=$(loop snapshot --fresh) || fail "snapshot exited non-zero"
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
  # No look of the loop found a model with no price (t_noprice holds one).
  [ "$(q '.needsYou.prices')" = null ] || fail "needsYou.prices is not null with no look for models with no price: $(q .needsYou.prices)"
  # No engine is stopped (health.test.sh t_stoppedneeds holds one).
  [ "$(q '.needsYou.stopped')" = null ] || fail "needsYou.stopped is not null with no engine stopped: $(q .needsYou.stopped)"
  # No open issue names a dependency in another repository: farDeps is an empty list (t_fardepsfail holds one).
  # No Pick settings decision is due: pick is an empty list. No card was picked by that rule: its seats are null (#1047).
  [ "$(q '.needsYou | del(.before, .pipeline, .engine, .testRules, .prices, .stopped) | map_values(map(del(.reviews, .track, .metrics, .parent, .start, .pickedAt, .priorSec, .totalSec, .earlier)))')" = "{\"waiting\":[{\"card\":\"c7\",\"issue\":7,\"title\":\"T7\",\"sentence\":\"a new button\",\"since\":\"${d}T00:05:00Z\",\"doneWhen\":null,\"split\":null,\"seats\":null,\"stalls\":0,\"files\":{\"count\":null,\"paths\":null},\"patch\":null,\"shots\":null}],\"blocked\":[{\"card\":\"c8\",\"issue\":8,\"title\":\"T8\",\"reason\":\"review 1: no answer\",\"tail\":\"\",\"since\":\"${d}T00:04:00Z\",\"doneWhen\":null,\"split\":null,\"seats\":null,\"stalls\":0}],\"pick\":[],\"farDeps\":[]}" ] \
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
    = '[19,{"queued":13,"you":2,"labelOrRule":4,"landed":0,"belt":0},[[8,"blocked"],[22,"you"],[23,"you"],[27,"awaiting-deploy"],[26,"awaiting-deploy"],[25,"awaiting-deploy"]]]' ] \
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
  # The time, free disk and GitHub read (ghRead: with no feed, the call's own time) are read again by each call; timesPlan is
  # added by the snapshot only (cputime.test.sh checks it).
  [ "$(q '.health | del(.time, .diskFreeKb, .ghRead, .timesPlan)')" = "$(loop health | jq -c 'del(.time, .diskFreeKb, .ghRead)')" ] || fail "health is not the health record"
  [ "$(q '.cost | del(.cards)')" = '{"today":31,"todayLeftOut":0,"todayEstimate":0,"week":37,"weekLeftOut":0,"weekEstimate":0,"perLanded":5.25,"perLandedLeftOut":0,"perLandedEstimate":0,"landedAfter":{"1":2,"2":1,"3":1,"more":0},"unpricedSteps":0,"unpriced":[],"picks":[],"trials":{"dropped":[],"flagged":[],"groups":[]},"replay":null}' ] || fail "cost: $(q .cost)"
  # Per card, the 7 days: a card landed on an earlier day (11) and the blocked ones (7, 8) are rows; one with no step
  # ended (1, 2) or last worked on before the 7 days (12) is not. The rows add up to the totals.
  [ "$(q '.cost.cards | map("\(.issue) \(.state) \(.today) \(.week)") | sort | join(", ")')" \
    = '"10 landed 9 9, 11 landed 0 6, 13 closed 3 3, 3 on the belt 2 2, 4 on the belt 3 3, 5 on the belt 3 3, 6 on the belt 3 3, 7 blocked 3 3, 8 blocked 2 2, 9 landed 3 3"' ] \
    && [ "$(q '.cost.cards | [.[0].card, .[-1].card, (map(.today) | add), (map(.week) | add), (.[0] | keys_unsorted)]')" = '["c10","c11",31,37,["card","issue","title","state","runs","today","week","todayEstimate","weekEstimate"]]' ] \
    || fail "cost per card: $(q .cost.cards)"
}
# GitHub does not say when: the same list, every since null. No issue carries the label: an empty list.
t_snapshotdeploy() { snapshotstart
  rm "$STUB/labelled"; [ "$(loop snapshot --fresh | jq -c '.awaitingDeploy | map([.issue, .since])')" = '[[25,null],[26,null],[27,null]]' ] || fail "awaitingDeploy without the label times"
  jq -c 'map(select(.labels | any(.name == "awaiting-deploy") | not))' "$STUB/issues.json" > "$STUB/issues.none" && mv "$STUB/issues.none" "$STUB/issues.json"
  # That snapshot also shows it left no copy of the records in its TMPDIR, and is the one the bad line below is held to.
  local before after; mkdir "$STUB/tmp"; before=$(TMPDIR=$STUB/tmp loop snapshot --fresh 2>/dev/null | jq -c '[.landed, .awaitingDeploy]')
  [ "$(jq -c '.[1]' <<<"$before")" = '[]' ] || fail "awaitingDeploy with no such issue is not an empty list: $before"
  [ -z "$(ls -A "$STUB/tmp")" ] || fail "a snapshot left its copy of the records behind: $(ls -A "$STUB/tmp")"
  # A line that does not check (#157): the snapshot is still given, with every card it gave before. The line is set
  # aside in quarantined.jsonl, and the snapshot's health names it. Bug: one bad line stopped every snapshot.
  # #290: the rows (snaprows) read the records before health's check set the line aside, and jq stopped on it.
  echo junk >> "$S/cards.jsonl"; after=$(loop snapshot --fresh 2>"$STUB/junk.err") || fail "a snapshot stopped on a line that does not check: $(cat "$STUB/junk.err")"
  ! grep -q 'parse error' "$STUB/junk.err" || fail "the snapshot's rows read the line before it was set aside: $(cat "$STUB/junk.err")"
  [ "$(jq -c '[.landed, .awaitingDeploy]' <<<"$after")" = "$before" ] && [ "$(jq -c '.health.quarantined | map(.field)' <<<"$after")" = '["(not JSON)"]' ] \
    || fail "the snapshot did not give the rest of the records, or its health does not name the line set aside: $(jq -c '[.landed, .health.quarantined]' <<<"$after")"
  ! grep -qx junk "$S/cards.jsonl" && [ "$(jq -sc 'map(.record)' "$S/quarantined.jsonl")" = '["junk"]' ] || fail "the snapshot did not set the bad line aside: $(cat "$S/quarantined.jsonl" 2>&1)"
}
# #4042: card 12, landed 10 days ago, is in pushedCards once its push is recorded today (t_snapshot: not before).
# It carries its landed commit: landed holds today's landings only, so without it the Foreman's wake for an issue landed
# on an earlier day and pushed today named no commit.
t_snapshotpushed() { snapshotstart; card 12 "$d" 'pushed:ok:{"sha":"abd","sec":5,"head":"abd"}'
  [ "$(loop snapshot --fresh | jq -c '.pushedCards | map(select(.card == "c12"))')" = "[{\"card\":\"c12\",\"issue\":12,\"sha\":\"abd\",\"time\":\"${d}T00:00:00Z\",\"day\":\"$d\"}]" ] \
    || fail "a card landed 10 days ago and pushed today is not in pushedCards: $(loop snapshot --fresh | jq -c .pushedCards)"
}
# A card's steps keep what the owner reads there: a NO-GO review its findings, and the blocked line its sentence and
# the end of its output, newlines kept. Without them the steps show only names, and the findings are lost.
# The Board draws the steps on a time axis and a review with its findings: each step has the time it ended (the
# queue's at the pick-up), and a review its counts. Without them the bars have no clock times and no findings chip.
t_snapshotsteps() { snapshotstart
  card 14 "$d" picked worktree brief build 'review:NO-GO:{"reason":"[P1] a.sh:1 wrong\n[P2] b.sh:2 slow","tail":"[P1] a.sh:1 wrong\n[P2] b.sh:2 slow","visible":"no","counts":{"P0":0,"P1":1,"P2":1,"P3":0}}' 'blocked:blocked:{"reason":"the changed tests failed; nothing landed.","tail":"ok 1\nFAIL x.test"}'
  out=$(loop snapshot --fresh) || fail "snapshot exited non-zero"
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
  local s c; s=$(loop snapshot --fresh | jq -c '.belt | map([.step, .review, .usd + 0])'); c=$(loop cards)
  [ "$s" = '[["review",2,5]]' ] && [ "$(jq -r '.cards[0].step' <<<"$c")" = review ] && ! grep -q '"x"' <<<"$c" \
    || fail "review 2 of 3, or cards gained the snapshot's fields: $s $c"
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
  out=$(loop snapshot --fresh 2>/dev/null) || fail "snapshot without gh exited non-zero"
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
  out=$(PATH=$STUB/nopy:$PATH loop snapshot --fresh 2>/dev/null) || fail "snapshot exited non-zero when the price table could not be run"
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
# One read: a card that lands while the snapshot is built (here just after the state database wrote the snapshot's copy of the records, before the rows, health and the prices are read) is in no part of that snapshot. Not as health asks gh: the snapshot asks GitHub before its build begins (snapask), so a card landed then is in the whole snapshot.
t_snapshotlate() { latestart
  # The hooks below are exported bash functions, not programs on PATH: on macOS p_path puts Homebrew's python3 and df
  # first on PATH, so a stub there is never run; the engine's bash runs a function of that name before any program.
  # The copy is the state database's answer to `since cards` (snapcopy(), lib/snapshot.sh).
  out=$(python3() { command python3 "$@"; local rc=$?; case "$*" in *state.py*" -o "*" since cards "*) [ -e "$STUB/was-late" ] || { cat "$STUB/late" >> "$ST/cards.jsonl"; : > "$STUB/was-late"; } ;; esac; return $rc; }
    export -f python3; loop snapshot --fresh 2>/dev/null) || fail "snapshot exited non-zero when a card landed as it was built"
  [ -e "$STUB/was-late" ] || fail "the late landing's hook never ran in the snapshot"
  grep -q '"card":"c5".*"landed"' "$S/cards.jsonl" || fail "the test's late landing was not written"
  [ "$(q '[(.belt | map(.card) | index("c5") != null), (.landed | map(.card)), (.health.unpushed | map(.card)), .health.newest[11:16]]')" = '[true,["c10","c9","c13"],["c10"],"00:05"]' ] \
    || fail "a card that landed while the snapshot was built is in part of it: $out"
  out=$(loop snapshot --fresh 2>"$STUB/err"); ! grep -qF 'made anew' "$STUB/err" || fail "a snapshot whose summary was kept said it is made anew (#282): $(cat "$STUB/err")"; [ "$(q '[(.landed | map([.card, .pushed])), (.health.unpushed | map(.card))]')" = '[[["c5",false],["c10",false],["c9",true],["c13",null]],["c10","c5"]]' ] \
    || fail "the next snapshot does not hold the landed card whole: $out"
  # A blocked card given back with `retry` leaves the views; what it cost stays in today's and the week's dollars.
  [ "$(q '.cost | [.today, .week]')" = '[31,37]' ] || fail "cost before the retry: $(q .cost)"
  loop retry 8 >/dev/null || fail "retry of the blocked #8 failed"; # what the snapshot had said when health read the free disk (df), in the build: gh is asked before the build begins
  out=$(df() { { grep -c "made anew" "$STUB/err" || :; } >> "$STUB/said"; command df "$@"; }; export -f df; loop snapshot --fresh 2>"$STUB/err") || fail "snapshot after a retry exited non-zero"; [ "$(sort -u "$STUB/said")" = 1 ] || fail "the snapshot after a retry rewrote the card records did not say it is made anew before health's long work, so a reader that stops it waits with no reason (#282): $(tr '\n' ' ' < "$STUB/said"), $(cat "$STUB/err")"
  [ "$(q '[(.cost | del(.cards)), .needsYou.blocked, (.health.blocked | length), ([.belt[], .landed[]] | map(.card) | index("c8")), (.cost.cards[] | select(.card == "c8") | [.state, .today, .week])]')" \
    = '[{"today":31,"todayLeftOut":0,"todayEstimate":0,"week":37,"weekLeftOut":0,"weekEstimate":0,"perLanded":4.8,"perLandedLeftOut":0,"perLandedEstimate":0,"landedAfter":{"1":3,"2":1,"3":1,"more":0},"unpricedSteps":0,"unpriced":[],"picks":[],"trials":{"dropped":[],"flagged":[],"groups":[]},"replay":null},[],0,null,["retried",2,2]]' ] || fail "a retried card's spend left the totals, or the card is still shown: $out"
  # The rest of a landed card's track. Cards 10 and 5 landed and are not at origin: both are on the belt, pushing.
  [ "$(after)" = '[["c10","push",14,"pushing","nt","n",null],["c5","push",14,"pushing","nt","n",null]]' ] || fail "two landed cards waiting for their push: $(after)"
}
# From where the case above ends: card 5 landed, the blocked #8 retried.
t_snapshotpush() { latestart; cat "$STUB/late" >> "$S/cards.jsonl"; loop retry 8 >/dev/null || fail "retry of the blocked #8 failed"
  # A push that fails after they landed is their step failed, not a card gone from the belt.
  mark 5 push "${d}T00:40:00Z" fail "$ahead"; out=$(loop snapshot --fresh 2>/dev/null) || fail "snapshot after a failed push exited non-zero"
  [ "$(after)" = '[["c10","push",14,"push failed; it is tried again","ft","f",""],["c5","push",14,"push failed; it is tried again","ft","f",""]]' ] || fail "a failed push is not the failed step of the cards it carried: $(after)"
  # Its step in "Every step" has the time of the card's last line, so the Board keeps every bar on the clock (one
  # bar without a time draws them all without their clock times and pauses).
  [ "$(q '.belt[] | select(.card == "c5") | .track.records[-1] | [.name, .state, .at[11:16]]')" = '["push failed; it is tried again","failed","00:30"]' ] \
    || fail "a failed push has no time in the card's steps: $(q '.belt[] | select(.card == "c5") | .track.records[-1]')"
  # Issue 1078: a push whose pre-push hook failed names the failed test and the push's log on the card, not only in
  # its push line, before its error.
  jq -cn --arg sha "$ahead" --arg t "${d}T00:45:00Z" '{card:"c5",issue:5,step:"push",time:$t,tokens:{claude:0,codex:0},result:"fail",sha:$sha,
    reason:"exit 1: the hook said no",kind:"check",check:"fast-checks",log:"/r/state/pushlogs/1.log"}' >> "$S/cards.jsonl"
  out=$(loop snapshot --fresh 2>/dev/null) || fail "snapshot after a failed check exited non-zero"
  [ "$(q '.belt[] | select(.card == "c5") | .track.reason')" = '"fast-checks failed. Log: /r/state/pushlogs/1.log. exit 1: the hook said no"' ] \
    || fail "a failed check does not name its test and the push's log on the card: $(q '.belt[] | select(.card == "c5") | .track')"
  # The push works. Card 5's pushed mark is new: it stays on the belt while GitHub closes its issue. Card 10's is an
  # hour old with no issue line (the loop died before it wrote one): while its issue may still be open (the open
  # issues could not be listed here) it stays on the belt, Push failed, not lost; it leaves once its issue is closed.
  echo "$ahead origin main" > "$S/pushed"; mark 10 pushed "$(date -u -d '1 hour ago' +%FT%TZ)" ok "$ahead"; mark 5 pushed "$(date -u +%FT%TZ)" ok "$ahead"
  out=$(loop snapshot --fresh 2>/dev/null) || fail "snapshot after the push exited non-zero"
  [ "$(after)" = '[["c10","issue",15,"GitHub did not close the issue","df","f","GitHub did not close the issue: no close of it was recorded"],["c5","issue",15,"waiting for GitHub to close the issue","dn","n",null]]' ] \
    || fail "a pushed card whose issue is not closed yet, or one with no issue line that left the belt: $(after)"
  # GitHub still shows the issue open: the card stays on the belt with Push failed and the issue line's reason.
  jq -cn --arg c c5 --arg t "$(date -u +%FT%TZ)" '{card:$c,issue:5,step:"issue",time:$t,tokens:{claude:0,codex:0},result:"fail",sha:"",reason:"GitHub still shows the issue open 60 s after the push of x"}' >> "$S/cards.jsonl"
  echo "[$(issue 5 2026-01-01)]" > "$STUB/issues.json"; out=$(loop snapshot --fresh 2>/dev/null) || fail "snapshot after the issue mark exited non-zero"
  [ "$(after)" = '[["c5","issue",15,"GitHub did not close the issue","df","f","GitHub did not close the issue: GitHub still shows the issue open 60 s after the push of x"]]' ] \
    || fail "a card whose issue GitHub did not close left the belt, or its Push is not failed with the reason: $(after)"
  # Its last step in "Every step" says why, as Push does, and when, so the Board's red bar has both.
  [ "$(q '.belt[] | select(.card == "c5") | .track.records[-1] | [.name, .state, (.at != null), .why]')" \
    = '["GitHub did not close the issue","failed",true,"GitHub did not close the issue: GitHub still shows the issue open 60 s after the push of x"]' ] \
    || fail "a failed close of the issue has no time or reason in the card's steps: $(q '.belt[] | select(.card == "c5") | .track.records[-1]')"
  # The issue is closed later, by hand: the card leaves the belt, and in the landed list its Push is done, not failed
  # with "Issue still open"; every step stays recorded, the failed close of the issue among them.
  echo '[]' > "$STUB/issues.json"; out=$(loop snapshot --fresh 2>/dev/null) || fail "snapshot after the issue closed exited non-zero"
  [ "$(after)" = '[]' ] && [ "$(q '.landed[] | select(.card == "c5") | .track | [.detailAt, (.detail[14:16] | map(.state)), .steps[5].state, .reason]')" = '[null,["done","done"],"done",null]' ] \
    && [ "$(q '.landed[] | select(.card == "c5") | .track.records | map(select(.name | IN("pushed", "issue not closed")) | [.name, .state])')" = '[["pushed","done"],["issue not closed","failed"]]' ] \
    || fail "a card whose issue was closed by hand is still on the belt, or its Push is not done: $(after) $(q '.landed[] | select(.card == "c5") | .track')"
}
# With push off nothing pushes a landed card until the owner presses Push landed: it is off the belt, never "pushing"
# (the owner read that as a push against the rule), and listed as landed and not pushed, waiting. With push on, pushing.
t_snapshotpushoff() { latestart; cat "$STUB/late" >> "$S/cards.jsonl"; loop control rules push=off >/dev/null || fail "push=off failed"
  out=$(loop snapshot --fresh 2>/dev/null) || fail "snapshot with push off exited non-zero"
  [ "$(q '[(.belt | map(select(.landed)) | length), (.health.unpushed | map(.card)), (.landed[] | select(.card == "c5") | [.step, .pushed, .track.label, .track.at, .track.steps[5].state, (.track.records | map(.state) | index("now"))])]')" \
    = '[0,["c10","c5"],["landed",false,"Landed, waiting for Push landed",null,"todo",null]]' ] || fail "a landed card with push off is on the belt or pushing: $out"
  loop control rules push=on >/dev/null; out=$(loop snapshot --fresh 2>/dev/null) || fail "snapshot with push on exited non-zero"
  [ "$(after)" = '[["c10","push",14,"pushing","nt","n",null],["c5","push",14,"pushing","nt","n",null]]' ] || fail "with push on a landed card is not pushing: $(after)"
  # A Push landed that failed does not put them back on the belt with push off: the failure is the Control tab's.
  mark 5 push "${d}T00:40:00Z" fail "$ahead"; loop control rules push=off >/dev/null; out=$(loop snapshot --fresh 2>/dev/null) || fail "snapshot after a failed push exited non-zero"
  [ "$(q '[(.belt | map(select(.landed)) | length), (.health.pushError != null), (.landed[] | select(.card == "c5") | .track.label)]')" \
    = '[0,true,"Landed, waiting for Push landed"]' ] || fail "with push off a failed push puts a landed card back on the belt: $out"
}
# Bug (#1279): six cards pushed in one batch, their issues closed, stayed "pushing" in the owner's view while a later
# push carried the next two, and that push named neither its cards nor how long it had run. After the first push the
# belt lists only the two, and health's push in progress, as the engine's push() records it, names them with the
# push's start. Its cards stay named after git push moves $PUSHED and before the push writes their pushed lines (the
# review of #1279: the Board said the push carried no card while it filed a flaky-test issue in that gap), and the
# start stays the push's own as its stage changes (the stage's since starts again).
t_snapshotbatch() {
  export TZ=UTC; setup '[]'; S=$ST; mkdir -p "$S"; local n t0 t1 shas=() d=$T/$CASE/run st pid
  for n in 1 2 3 4 5 6 7 8; do echo "$n" > "$R/b$n.txt"; git -C "$R" add -A; git -C "$R" commit -qm "card $n"; shas+=("$(git -C "$R" rev-parse HEAD)"); done
  t0=$(date -u -d '10 minutes ago' +%FT%TZ); t1=$(date -u -d '2 minutes ago' +%FT%TZ)
  for n in 1 2 3 4 5 6 7 8; do
    jq -cn --arg c "c$n" --argjson i "$n" --arg t "$t0" --arg s "${shas[n-1]}" '
      {card:$c,issue:$i,step:"picked",time:$t,tokens:{claude:0,codex:0},result:"ok",sha:"",reason:"",title:"T\($i)"},
      {card:$c,issue:$i,step:"landed",time:$t,tokens:{claude:0,codex:0},result:"ok",sha:$s,reason:"",product:false}' >> "$S/cards.jsonl"
  done
  # The first push carried cards 1 to 6 (main at card 6) and GitHub closed their issues; 7 and 8 are still open.
  for n in 1 2 3 4 5 6; do
    jq -cn --arg c "c$n" --argjson i "$n" --arg t "$t1" --arg s "${shas[n-1]}" --arg h "${shas[5]}" '
      {card:$c,issue:$i,step:"pushed",time:$t,tokens:{claude:0,codex:0},result:"ok",sha:$s,reason:"",sec:100,head:$h},
      {card:$c,issue:$i,step:"issue",time:$t,tokens:{claude:0,codex:0},result:"ok",sha:"",reason:""}' >> "$S/cards.jsonl"
  done
  git -C "$R" push -q origin "${shas[5]}:refs/heads/main" || fail "the first push's commit could not be put on origin"
  echo "${shas[5]} origin main" > "$S/pushed"
  { issue 7 2026-01-01; issue 8 2026-01-01; } | jq -cs . > "$STUB/issues.json"
  # The second push, of main at card 8, by the loop's push(): its pre-push hook writes nothing and holds until go; the
  # push then holds before its first pushed line until rows (record, wrapped), with $PUSHED already at card 8.
  mkdir -p "$d"; printf '#!/usr/bin/env bash\n: > %q/hook\nuntil [ -e %q/go ]; do sleep 0.05; done\n' "$d" "$d" > "$R/.git/hooks/pre-push" && chmod +x "$R/.git/hooks/pre-push" # sleep: the hook's poll for its release
  # shellcheck disable=SC2034 # HERE is read by the lines of conveyor.sh and commands/run.sh run by the eval
  ( HERE=$SRC; export CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards
    eval "$(sed -n '/^\. "\$HERE\/lib\/portable.sh"/,/^\. "\$HERE\/lib\/records.sh"/p' "$SRC/conveyor.sh")"
    eval "$(grep '^\. "\$HERE/lib/' "$SRC/commands/run.sh")"
    eval "$(declare -f record | sed '1s/^record /realrecord /')"
    record() { [ "$3" != pushed ] || { : > "$d/gap"; until [ -e "$d/rows" ]; do sleep 0.05; done; }; realrecord "$@"; } # sleep: the poll for the case's release
    names || exit 1; push c8 8 ) > "$d/push.out" 2>&1 & pid=$!
  wait_until '[ -e "$d/hook" ]' "cat '$d/push.out'" || fail "the second push's hook did not start"
  out=$(loop snapshot --fresh 2>/dev/null) || fail "snapshot during the second push exited non-zero"
  [ "$(jq -c '[.belt[] | [.card, .step, .track.label]]' <<<"$out")" = '[["c7","push","pushing"],["c8","push","pushing"]]' ] \
    || fail "after the first push the belt does not list only the two cards of the second: $(jq -c '[.belt[] | [.card, .step, .track.label]]' <<<"$out")"
  [ "$(jq -c '.health.pushing | [.cards, .stage, (.started | type), has("base")]' <<<"$out")" = '[[{"card":"c7","issue":7},{"card":"c8","issue":8}],"hook","string",false]' ] \
    || fail "the push in progress does not name its cards or how long it has run: $(jq -c .health.pushing <<<"$out")"
  st=$(jq -r .health.pushing.started <<<"$out")
  # The next stage begins in a later second than the push did, so its since and the push's start differ.
  wait_until "[ \"\$(date -u +%FT%TZ)\" \\> '$st' ]" || fail "the clock did not pass the push's start"
  : > "$d/go"; wait_until '[ -e "$d/gap" ]' "cat '$d/push.out'" || fail "the second push did not reach its pushed lines"
  [ "$(cat "$S/pushed")" = "${shas[7]} origin main" ] || fail "the push had not moved \$PUSHED before its pushed lines: $(cat "$S/pushed")"
  out=$(loop snapshot --fresh 2>/dev/null) || fail "snapshot after the remote took the second push exited non-zero"
  [ "$(jq -c --arg st "$st" '.health.pushing | [.cards, .stage, .started == $st, .since > $st]' <<<"$out")" = '[[{"card":"c7","issue":7},{"card":"c8","issue":8}],"pushed",true,true]' ] \
    || fail "a push the remote took does not name the cards it carries before their pushed lines, or not its own start ($st): $(jq -c .health.pushing <<<"$out")"
  : > "$d/rows"; wait "$pid" || fail "the second push failed: $(cat "$d/push.out")"
}
