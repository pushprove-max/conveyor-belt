#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases (#648): a parent issue and its parts, GitHub sub-issues of it (the stub gh: $STUB/subs, a line
# "<parent> <part>" for each). The pick (jq/upnext.jq) never takes a parent, umbrellas() (lib/slices.sh) closes one
# whose parts are each closed or landed, `conveyor.sh parts` attaches parts, and the snapshot names each part's parent.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# Parent #10, the oldest issue, with two open parts #11 and #12. Bug caught: the loop picked the parent, which is
# built by its parts, so its work was built twice. Then, with one part closed, the parent stays open; with both closed,
# the loop's turn closes it with a comment that names them. Bug caught: a parent stayed open after its last part closed.
t_partsloop() {
  setup "[$(issue 10 2026-11-01), $(issue 11 2026-11-02), $(issue 12 2026-11-03)]"
  printf '10 11\n10 12\n' > "$STUB/subs"
  fx_in 'locked pick "" "" "$(asked)"'
  [ "$RC" = 0 ] && [ "$(cut -d' ' -f2 "$T/$CASE/run.out")" = 11 ] || fail "the pick did not take the first part #11 over its parent #10 (exit $RC): $(cat "$T/$CASE/run.out")"
  # A run limited to the parent (--only 10) builds its parts: #11 has its card, so it takes #12, and says #10 is a
  # parent. Bug caught: --only admitted #10 alone and dropped it as a parent, and said a label kept #10 off the belt.
  fx_in 'ONLY="[10]"; onlyreport; locked pick "" "" "$(asked)"'
  [ "$RC" = 0 ] && grep -qx 'c[^ ]* 12 .*' "$T/$CASE/run.out" && grep -qF 'conveyor: #10 is a parent: it is not built, its open parts #11, #12 are built in its place' "$T/$CASE/run.out" \
    && ! grep -q 'by a label' "$T/$CASE/run.out" || fail "a run limited to the parent #10 did not take its part #12, or did not say #10 is a parent (exit $RC): $(cat "$T/$CASE/run.out")"
  echo "[$(issue 10 2026-11-01), $(issue 12 2026-11-03)]" > "$STUB/issues.json"
  fx_in 'umbrellas "$(asked)"'
  [ ! -e "$STUB/closed" ] || fail "a parent with a part still open was closed: $(cat "$STUB/closed") $(cat "$T/$CASE/run.out")"
  echo "[$(issue 10 2026-11-01)]" > "$STUB/issues.json"
  fx_in 'umbrellas "$(asked)"'
  [ "$(cat "$STUB/closed" 2>/dev/null)" = 10 ] && grep -qF '(#11, #12)' "$STUB/close-comments" \
    || fail "the parent was not closed with a comment naming its parts once both were closed: $(cat "$STUB/closed" "$STUB/close-comments" 2>/dev/null) $(cat "$T/$CASE/run.out")"
}

# Push off (#875): the split umbrella #10, held, whose two parts #11 and #12 have each landed and are still open (a
# landed issue stays open until the owner's push). The loop's turn (umbrellas()) closes it, with a comment that says
# which parts landed, and releases it. Bug caught: the parent waited for its parts to close, which with push off never
# happened, so it stayed open and held, looking like work waiting to build.
t_partslanded() {
  setup "[$(issue 10 2026-11-01), $(issue 11 2026-11-02), $(issue 12 2026-11-03)]"
  printf '10 11\n10 12\n' > "$STUB/subs"
  jq -c '.rules.push = false | .held = [10]' "$ST/control.json" > "$STUB/c.new" && mv "$STUB/c.new" "$ST/control.json"
  { landed 11; landed 12; } >> "$ST/cards.jsonl"
  fx_in 'umbrellas "$(asked)"'
  [ "$(cat "$STUB/closed" 2>/dev/null)" = 10 ] && grep -qF '(#11, #12; landed, not closed yet: #11, #12)' "$STUB/close-comments" \
    && [ "$(jq -c .held "$ST/control.json")" = '[]' ] \
    || fail "the parent whose parts both landed was not closed and released with push off: $(cat "$STUB/closed" "$STUB/close-comments" 2>/dev/null) $(jq -c .held "$ST/control.json") $(cat "$T/$CASE/run.out")"
}

# Push off (#875): #30's card landed and its commit is not pushed, so the issue is still open. The snapshot shows it as
# landed, not pushed: its held reason says so, the split counts it apart (not held by a rule, not on the belt), the
# queue does not list it, and its parent #40 counts it as a part done. Push on, it is on the belt, pushing, as before.
# Bug caught: with push off a landed issue was counted on the belt, and the Board showed it as skipped by a rule.
t_partsunpushed() {
  setup "[$(issue 30 2026-11-01), $(issue 40 2026-11-02), $(issue 41 2026-11-03)]"
  printf '40 30\n40 41\n' > "$STUB/subs"
  echo x > "$R/n.txt" && git -C "$R" add -A && git -C "$R" commit -qm next || fail "main's commit"
  jq -c '.rules.push = false' "$ST/control.json" > "$STUB/c.new" && mv "$STUB/c.new" "$ST/control.json"
  jq -cn --arg s "$(git -C "$R" rev-parse HEAD)" 'def l($t; $x): {card: "c1-30", issue: 30, time: $t, tokens: {claude: 0, codex: 0}, result: "ok", sha: "", reason: ""} + $x;
    l("2026-11-10T09:00:00Z"; {step: "picked", title: "title 30"}), l("2026-11-10T10:00:00Z"; {step: "landed", sha: $s, product: false})' >> "$ST/cards.jsonl"
  loop snapshot > "$T/$CASE/snap.json" || fail "the snapshot failed: $(head -c 400 "$T/$CASE/snap.json")"
  [ "$(jq -c '.open | [(.held[] | select(.issue == 30) | .reasons), .split, (.umbrellas[] | select(.issue == 40) | [.done, .inFlight])]' "$T/$CASE/snap.json")" \
    = '[[{"kind":"card","step":"landed","card":"c1-30","notPushed":true}],{"queued":1,"you":0,"labelOrRule":1,"landed":1,"belt":0},[1,[]]]' ] \
    || fail "the landed, unpushed #30 is not shown as landed, not pushed: $(jq -c .open "$T/$CASE/snap.json")"
  jq -e '[.queue.order[].issue] == [41]' "$T/$CASE/snap.json" >/dev/null || fail "the queue is not #41 alone: $(jq -c '.queue.order' "$T/$CASE/snap.json")"
  jq -c '.rules.push = true' "$ST/control.json" > "$STUB/c.new" && mv "$STUB/c.new" "$ST/control.json"
  loop snapshot --fresh > "$T/$CASE/snap.json" || fail "the snapshot with push on failed: $(head -c 400 "$T/$CASE/snap.json")"
  [ "$(jq -c '[.open.split, ([.belt[] | select(.issue == 30) | .track.label]), (.open.umbrellas[] | select(.issue == 40) | .done)]' "$T/$CASE/snap.json")" \
    = '[{"queued":1,"you":0,"labelOrRule":1,"landed":0,"belt":1},["pushing"],0]' ] \
    || fail "with push on the landed #30 is not on the belt, pushing, as before: $(jq -c '[.open, .belt]' "$T/$CASE/snap.json")"
}

# A run limited to the parent #10 takes the open follow-up #13 its landed part #11 filed, which its other part #12
# (`Depends on: #11`) waits for. Bug caught: --only took the parts after the follow-ups, and only the open ones, so it
# left out #13 and #12 waited for it with nothing to build.
t_partsfollowup() {
  setup "[$(issue 10 2026-11-01), $(issue 12 2026-11-03 | jq -c '.body = "body\nDepends on: #11"'), $(issue 13 2026-11-04)]"
  printf '10 11\n10 12\n' > "$STUB/subs"
  landed 11 '[13]' >> "$ST/cards.jsonl"
  fx_in 'ONLY="[10]"; locked pick "" "" "$(asked)"'
  [ "$RC" = 0 ] && grep -qx 'c[^ ]* 13 .*' "$T/$CASE/run.out" || fail "a run limited to the parent #10 did not take #13, the follow-up of its part #11 (exit $RC): $(cat "$T/$CASE/run.out")"
}

# `parts 10 11 12` attaches #11 and #12 to #10; the snapshot names #10 as the umbrella of #11 in the queue and of #12
# on the belt, gives #10 one entry with 0 of 2 parts done and #12 in flight, and names #20 as the umbrella of its
# blocked part #21, with its closed part #22 among its closed ones. Bug caught: the Board and /units could not tell
# which parent an issue or card is a part of, and the Board could not tell which part had landed.
t_partscmd() {
  setup "[$(issue 10 2026-11-01), $(issue 11 2026-11-02), $(issue 12 2026-11-03), $(issue 20 2026-11-04), $(issue 21 2026-11-05)]"
  loop parts 10 11 12 > "$T/$CASE/parts.out" 2>&1 || fail "parts failed: $(cat "$T/$CASE/parts.out")"
  [ "$(cat "$STUB/subs" 2>/dev/null)" = $'10 11\n10 12' ] || fail "parts did not attach #11 and #12 to #10: $(cat "$STUB/subs" 2>/dev/null) $(cat "$T/$CASE/parts.out")"
  printf '20 21\n20 22\n' >> "$STUB/subs"
  # #12's card is on the belt (picked, not ended); #21's is blocked.
  jq -cn 'def l($c; $n; $s; $r; $t): {card: $c, issue: $n, step: $s, time: $t, tokens: {claude: 0, codex: 0}, result: $r, sha: "", reason: ""};
    l("c1-12"; 12; "picked"; "ok"; "2026-11-10T09:00:00Z") + {title: "title 12"}, l("c2-21"; 21; "picked"; "ok"; "2026-11-10T09:00:00Z") + {title: "title 21"},
    l("c2-21"; 21; "blocked"; "blocked"; "2026-11-10T10:00:00Z") + {reason: "review 1: no answer"}' >> "$ST/cards.jsonl"
  loop snapshot > "$T/$CASE/snap.json" || fail "the snapshot failed: $(head -c 400 "$T/$CASE/snap.json")"
  [ "$(jq -c '[(.queue.order[] | select(.issue == 11) | .umbrella), (.belt[] | select(.issue == 12) | .umbrella), (.needsYou.blocked[] | select(.issue == 21) | .umbrella)]' "$T/$CASE/snap.json")" = '[10,10,20]' ] \
    || fail "the snapshot does not name each part's parent: $(jq -c '[.queue.order, .belt, .needsYou.blocked] | map(map({issue, umbrella}))' "$T/$CASE/snap.json")"
  [ "$(jq -c '.open.umbrellas | map(select(.issue == 10))' "$T/$CASE/snap.json")" = '[{"issue":10,"title":"title 10","parts":["#11","#12"],"done":0,"all":2,"inFlight":[12],"closed":[]}]' ] \
    || fail "the snapshot does not give #10 one entry with 0 of 2 parts done and #12 in flight: $(jq -c .open.umbrellas "$T/$CASE/snap.json")"
  [ "$(jq -c '.open.umbrellas | map(select(.issue == 20) | {done, all, closed})' "$T/$CASE/snap.json")" = '[{"done":1,"all":2,"closed":["#22"]}]' ] \
    || fail "the snapshot does not name #22 as the closed part of #20: $(jq -c .open.umbrellas "$T/$CASE/snap.json")"
  jq -e '[.queue.order[].issue] | index(10) == null' "$T/$CASE/snap.json" >/dev/null || fail "the parent #10 is in the queue: $(jq -c '.queue.order' "$T/$CASE/snap.json")"
}

# A pick without --only never reads the records --only grows from (#654): a card record and a retried line whose grown
# field is no object cannot be read as one, so upnext() given them still lists #5. Bug caught: every pick and snapshot
# built those records (the card records mapped, the retried lines scanned) before it checked for --only, work it never
# used, and a line like either of these stopped the whole order.
t_partsnoonly() {
  setup "[$(issue 5 2026-11-01)]"
  landed 4 | jq -c '. + {grown: "unread"}' > "$T/$CASE/hrec" && jq -cn '{card:"c0-4",issue:4,step:"retried",grown:"unread"}' > "$T/$CASE/hold" || fail "the fixture could not be written"
  fx_in 'UPREC=$T/$CASE/hrec UPOLD=$T/$CASE/hold upnext "$(asked)" "" all | jq -c "map(.number)"'
  [ "$RC" = 0 ] && [ "$(cat "$T/$CASE/run.out")" = '[5]' ] || fail "upnext without --only read the records --only grows from (exit $RC): $(cat "$T/$CASE/run.out")"
}

# Bug: umbrellas() gave jq the open list as one argument (--argjson); with the bodies (FIELDS) a list over 128 KiB
# fails to start jq on Linux, its error went to /dev/null, and no parent was closed: eleven parents whose parts were all
# closed stayed open. Here #13's body alone is 140 KiB; #10's parts #11 and #12 are closed, so #10 is closed.
t_partsbig() {
  setup "[$(issue 10 2026-11-01), $(issue 13 2026-11-04)]"
  printf '10 11\n10 12\n' > "$STUB/subs"
  jq -c 'map(if .number == 13 then .body = ("x" * 143360) else . end)' "$STUB/issues.json" > "$STUB/i.new" && mv "$STUB/i.new" "$STUB/issues.json"
  [ "$(wc -c < "$STUB/issues.json")" -gt 131072 ] || fail "the open list over 128 KiB was not made"
  fx_in 'umbrellas "$(asked)"'
  [ "$(cat "$STUB/closed" 2>/dev/null)" = 10 ] && grep -qF '(#11, #12)' "$STUB/close-comments" \
    || fail "with the open list over 128 KiB, the parent #10 whose parts are closed was not closed: $(cat "$STUB/closed" "$STUB/close-comments" 2>/dev/null) $(cat "$T/$CASE/run.out")"
}
