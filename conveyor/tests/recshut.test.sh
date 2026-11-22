#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: shutting the card of a closed issue, giving a reopened one back, and an issue already fixed.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# Bugs: a blocked card whose issue was closed (for any reason) stays under "Needs you" and in health's blocked list,
# with no way to clear it; it does not end closed with a line saying why; its kept patch is deleted; the blocked card
# of an issue that was not closed leaves too; it is given back while an open list still shows it but GitHub says it is
# closed; once it is opened again, no turn of the loop gives it back with no `retry` (#599), or its lines stay in the
# card records. The turn's parts are called as a turn calls them: shut() under the lock with the
# issues found closed, then reopened() with the open list.
# shutrec <issue>...: the blocked card c0-<issue> of each, its patch (a.txt gets the line two) kept in kept/c0-<issue>/.
shutrec() {
  local n; mkdir -p "$ST"
  for n; do
    mkdir -p "$ST/kept/c0-$n" && echo two >> "$R/a.txt" && git -C "$R" diff > "$ST/kept/c0-$n/c0-$n.patch" && git -C "$R" reset -q --hard || fail "the kept patch of c0-$n"
    landed "$n" | jq -c --arg k "kept/c0-$n" '(.step = "picked"), (.step = "blocked" | .result = "blocked" | .reason = "build: it failed" | .kept = $k)' >> "$ST/cards.jsonl"
  done
}
t_shut() {
  local c7=c0-7 c8=c0-8 open
  setup "$(jq -cs . <(issue 7 2026-01-01) <(issue 8 2026-02-01))"; shutrec 7 8; open="[$(issue 7 2026-01-01)]"
  [ "$(loop health | jq -c '.blocked | map(.issue)')" = '[7,8]' ] || fail "#7 and #8 were not blocked to start with: $(loop health)"
  # #7 is closed on GitHub: the turn shuts its card and leaves #8's blocked.
  fx_in 'locked shut "[7]"'
  [ "$RC" = 0 ] || fail "shut [7] exited $RC: $(cat "$T/$CASE/run.out")"
  [ "$(loop health | jq -c '[(.blocked | map(.card)), (.waiting | map(.card))]')" = "[[\"$c8\"],[]]" ] || fail "health's blocked lists after #7 was closed: $(loop health | jq -c '[.blocked, .waiting]')"
  snap=$(loop snapshot --fresh) || fail "snapshot exited non-zero"
  [ "$(jq -c '[.needsYou.blocked[], .needsYou.waiting[]] | map(.issue)' <<<"$snap")" = '[8]' ] || fail "Needs you still lists the closed #7: $(jq -c .needsYou <<<"$snap")"
  [ "$(loop cards | jq -r --arg c "$c7" '.cards[] | select(.card == $c) | .step')" = closed ] || fail "#7's card does not end closed: $(loop cards | jq -c .cards)"
  [ "$(loop cards | jq -c '[.landed, .blocked]')" = '[0,1]' ] || fail "the cards summary counts the closed #7, which landed nothing, as landed: $(loop cards | jq -c '[.landed, .blocked]')"
  [ "$(st "select(.card == \"$c7\") | .step" | tail -n 1)" = closed ] \
    && [ "$(st "select(.card == \"$c7\" and .step == \"closed\") | [.result, .reason] | join(\"|\")")" = 'ok|the issue was closed by hand while the card was blocked' ] \
    || fail "no closed line says #7 was closed while its card was blocked: $(grep "$c7" "$ST/cards.jsonl")"
  # Bug: the owner's report still lists the closed #7 as blocked, for the owner.
  out=$(CONVEYOR_MAIN=$R bash "$SRC/report.sh") || fail "report exited non-zero"
  [ "$(grep -c '^blocked, for ' <<<"$out")" = 1 ] && grep -q "^blocked, for .*: $c8 issue #8: " <<<"$out" || fail "the report's blocked cards after #7 was closed: $out"
  grep -Eq '^cards landed +0$' <<<"$out" || fail "the report counts the closed #7, which landed nothing, as landed: $out"
  [ -s "$ST/kept/$c7/$c7.patch" ] || fail "the kept patch of #7's card is gone"
  loop check || fail "the records do not check after a closed issue's card was closed"
  # The open list still shows #7, its card shut: it is asked whether it was opened again; GitHub says closed, so
  # nothing is given back.
  echo "$open" > "$STUB/closed-issues.json"; rm -f "$STUB/closed-viewed"
  fx_in "reopened '$open'"
  [ "$(cat "$STUB/closed-viewed" 2>&1)" = 7 ] && [ ! -s "$ST/retried.jsonl" ] && [ "$(st "select(.card == \"$c7\") | .step" | tail -n 1)" = closed ] \
    || fail "#7, shown open but closed on GitHub, was not asked, or was given back (exit $RC): $(cat "$ST/retried.jsonl" "$STUB/closed-viewed" 2>&1)"
  # Opened again, #7 is given back with no retry: its shut card's lines move to the retried file, its kept work stays,
  # and #8's card is left as it was.
  echo '[]' > "$STUB/closed-issues.json"
  fx_in "reopened '$open'"
  [ "$(jq -r .card "$ST/retried.jsonl" | sort -u)" = "$c7" ] && ! grep -q "\"card\":\"$c7\"" "$ST/cards.jsonl" \
    || fail "the reopened #7's shut card did not move alone out of the card records (exit $RC): $(cat "$ST/retried.jsonl" 2>&1)"
  [ -s "$ST/kept/$c7/$c7.patch" ] && [ "$(st "select(.card == \"$c8\") | .step" | tr '\n' ' ')" = 'picked blocked ' ] || fail "the kept patch of #7 went, or #8's card changed"
}

# t_shut calls shut() and reopened() with the issues it names; this case runs the loop, as only a turn shows run()
# (lib/run.sh) asking GitHub for each blocked card's issue and taking the closed ones out of the open list it read.
# Bugs: the stale open list still shows the closed #7, and the turn picks it again or leaves it in the sample's list
# (issues.json); #8, open but left out of the list, is taken for closed and shut; once #7 is opened again, its new
# card does not start from the kept patch.
t_shutturn() {
  local c7=c0-7 c8=c0-8
  setup "[$(issue 7 2026-01-01)]"; shutrec 7 8; cp "$STUB/issues.json" "$STUB/closed-issues.json"
  loop run 1 >/dev/null 2>&1
  [ "$(sort -n "$STUB/closed-viewed" 2>&1 | tr '\n' ' ')" = '7 8 ' ] || fail "the turn did not ask GitHub for each blocked card's issue: $(cat "$STUB/closed-viewed" 2>&1)"
  [ "$(st "select(.card == \"$c7\") | .step" | tail -n 1)" = closed ] && [ "$(st 'select(.issue == 7) | .card' | sort -u)" = "$c7" ] \
    || fail "the turn did not shut #7's card, or picked the closed #7 again: $(st 'select(.issue == 7) | "\(.card) \(.step)"' | tr '\n' ,)"
  [ "$(jq -c 'map(.number)' "$ST/issues.json")" = '[]' ] || fail "the sample's open list still counts the closed #7: $(cat "$ST/issues.json")"
  [ "$(st "select(.card == \"$c8\") | .step" | tr '\n' ' ')" = 'picked blocked ' ] || fail "#8, open but not in the open list, was shut: $(grep "$c8" "$ST/cards.jsonl")"
  echo '[]' > "$STUB/closed-issues.json"; echo 'cat a.txt > "$STUB/resumed"; exit 1' > "$STUB/build"
  loop run 1 >/dev/null 2>&1
  grep -q "\"card\":\"$c7\"" "$ST/retried.jsonl" && ! grep -q "\"card\":\"$c7\"" "$ST/cards.jsonl" || fail "the turn did not give back the reopened #7"
  [ -n "$(st "select(.issue == 7 and .step == \"worktree\" and (.reason | contains(\"kept patch of card $c7\"))) | .card")" ] \
    && [ "$(cat "$STUB/resumed" 2>&1)" = $'one\ntwo' ] || fail "#7, reopened, did not start from its kept patch: $(st 'select(.issue == 7) | "\(.step) \(.reason)"'; cat "$STUB/resumed" 2>&1)"
}

# The Board's Close shuts the card itself (`shut`), with no turn of the loop: a stopped loop would leave it under
# Needs you for good. Bug: #8's card stays blocked until a loop runs, or shut touches the records of an issue with
# no blocked card. A case of its own on a main of its own, beside t_shut. shut that shuts nothing says why and exits 1
# (#1030): bugs, it said nothing and exited 0 for #9, which has no card, or shut #10, whose card landed.
t_shutboard() {
  local c8=c0-8 out
  setup "[$(issue 8 2026-02-01)]"; shutrec 8
  jq -cn '{card:"c0-10",issue:10,time:"2026-01-01T00:00:00Z",tokens:{claude:0,codex:0},result:"ok",sha:"",reason:""} | (. + {step:"picked"}), (. + {step:"landed",sha:"abc1234",product:true})' >> "$ST/cards.jsonl"
  before=$(cat "$ST/cards.jsonl"); out=$(loop shut 9 2>&1); RC=$?
  [ "$RC" = 1 ] && grep -qF 'issue #9 has no card; nothing changed' <<<"$out" || fail "shut of #9, which has no card, did not say so and exit 1 (exit $RC): $out"
  out=$(loop shut 10 2>&1); RC=$?
  [ "$RC" = 1 ] && grep -qF 'issue #10 has a card that landed' <<<"$out" || fail "shut of #10, whose card landed, was not refused with why (exit $RC): $out"
  [ "$(cat "$ST/cards.jsonl")" = "$before" ] || fail "shut 9 or shut 10 changed the card records"
  loop shut 8 >/dev/null || fail "shut 8 exited non-zero"
  [ "$(loop health | jq -c '.blocked | map(.issue) | index(8)')" = null ] && [ "$(loop snapshot --fresh | jq -c '[.needsYou.blocked[], .needsYou.waiting[]] | map(.issue) | index(8)')" = null ] \
    || fail "#8 is still under Needs you after shut 8: $(loop health | jq -c '[.blocked, .waiting]')"
  [ "$(st "select(.card == \"$c8\") | [.step, .reason] | join(\"|\")" | tail -n 1)" = 'closed|the issue was closed by hand while the card was blocked' ] \
    || fail "no closed line says #8 was shut: $(grep "$c8" "$ST/cards.jsonl")"
  loop check || fail "the records do not check after shut"
}

# The owner's stop (`shut`, #1030) is known by the cards shut ended, not by the reason of their blocked line. Bugs:
# #7, which the loop blocked first with its own reason once shut killed its process, and #8, whose reason block()
# added to (a comment GitHub refused), closed as shut because their issue was closed, so the turn's reopened() gave
# both open issues back with no retry; and the stopped land-branch card $b was told to `retry <card id>`, which
# refuses an issue-0 card that is no main-red fix card. shut() and reopened() are called as shut and a turn call them.
t_shutown() {
  local b=c20261120T013602-x-0 out
  setup "$(jq -cs . <(issue 7 2026-01-01) <(issue 8 2026-02-01))"; shutrec 7 8
  jq -cn --arg b "$b" '{card:$b,issue:0,time:"2026-11-01T00:00:00Z",tokens:{claude:0,codex:0},result:"ok",sha:"",reason:""}
    | (. + {step:"picked",title:"hand",branch:"hand/one"}), (. + {step:"blocked",result:"blocked",reason:"review: the card process ended"})' >> "$ST/cards.jsonl"
  out=$(jq -c 'if .card == "c0-8" and .step == "blocked" then .reason = "shut by the owner. GitHub refused the comment" else . end' "$ST/cards.jsonl") && printf '%s\n' "$out" > "$ST/cards.jsonl"
  fx_in "locked shut '[7,8]' '[\"c0-7\"]' && locked shut $b '[\"$b\"]' && reopened '$(cat "$STUB/issues.json")'"
  [ "$RC" = 0 ] || fail "shut exited $RC: $(cat "$T/$CASE/run.out")"
  [ "$(st 'select(.step == "closed") | "\(.card) \(.reason)"' | tr '\n' '|')" = "c0-7 shut by the owner|c0-8 shut by the owner|$b shut by the owner|" ] \
    || fail "a card the owner shut did not close as shut by the owner, or reopened() gave it back: $(st 'select(.step == "closed" or .step == "blocked") | "\(.card) \(.step) \(.reason)"')"
  grep -qF "card $b was shut by the owner; the card is closed, its kept work where it was, and its branch left as it is" "$T/$CASE/run.out" \
    && ! grep -qF "retry $b" "$T/$CASE/run.out" || fail "shut of the land-branch card $b named a retry that refuses it: $(cat "$T/$CASE/run.out")"
}

# A hand change landed by land-branch is a card of issue 0. Blocked by its review, then landed by a second land-branch,
# it stayed under Needs you for good: shut took only a main-red fix card's id (#878). Bugs: `shut <its card id>` is
# refused, or loses its kept patch or moves its branch; Needs you does not say that its branch's change is already on
# main, or says so of a branch whose change is not; shut takes the id of an issue-0 card that is neither kind.
t_shutbranch() {
  local c=c20261120T013602-x-0 b=c20261120T013603-x-0 o=c20261120T013604-x-0 snap before tip
  setup '[]'; mkdir -p "$ST/kept/$c"
  # hand/one: its change is on main (made at main's tip). hand/two: a change main does not have.
  git -C "$R" branch hand/one && git -C "$R" switch -q -c hand/two && echo three >> "$R/a.txt" && git -C "$R" commit -qam three \
    && git -C "$R" switch -q - && echo two >> "$R/a.txt" && git -C "$R" diff > "$ST/kept/$c/$c.patch" && git -C "$R" reset -q --hard \
    || fail "the branches and the kept patch of $c"
  tip=$(git -C "$R" rev-parse hand/one)
  jq -cn --arg c "$c" --arg b "$b" --arg o "$o" --arg k "kept/$c" '{issue:0,time:"2026-11-01T00:00:00Z",tokens:{claude:0,codex:0},result:"ok",sha:"",reason:""}
    | (. + {card:$c,step:"picked",title:"hand one",branch:"hand/one"}), (. + {card:$c,step:"blocked",result:"blocked",reason:"NO-GO: review 1.",kept:$k}),
      (. + {card:$b,step:"picked",title:"hand two",branch:"hand/two"}), (. + {card:$b,step:"blocked",result:"blocked",reason:"NO-GO: review 1."}),
      (. + {card:$o,step:"picked",title:"neither"}), (. + {card:$o,step:"blocked",result:"blocked",reason:"build: it failed"})' > "$ST/cards.jsonl"
  snap=$(loop snapshot --fresh) || fail "snapshot exited non-zero"
  # The reason stays as recorded: the Board reads a review's finding and the failing tests by its form.
  [ "$(jq -c '.needsYou.blocked | map(select(.onMain == true)) | map(.card)' <<<"$snap")" = "[\"$c\"]" ] \
    && jq -e --arg c "$c" '.needsYou.blocked[] | select(.card == $c) | .reason == "NO-GO: review 1."' <<<"$snap" >/dev/null \
    || fail "Needs you does not say that hand/one alone is already on main, or changed its reason: $(jq -c '.needsYou.blocked | map([.card, .onMain, .reason])' <<<"$snap")"
  before=$(cat "$ST/cards.jsonl")
  ! loop shut "$o" >/dev/null 2>&1 && [ "$(cat "$ST/cards.jsonl")" = "$before" ] || fail "shut took $o, an issue-0 card that is no main-red fix card and no land-branch card"
  loop shut "$c" >/dev/null || fail "shut $c exited non-zero"
  [ "$(st "select(.card == \"$c\") | [.step, .reason] | join(\"|\")" | tail -n 1)" = "closed|the issue was closed by hand while the card was blocked" ] \
    || fail "no closed line says $c was shut: $(grep "$c" "$ST/cards.jsonl")"
  [ "$(loop snapshot --fresh | jq -c '.needsYou.blocked | map(.card)')" = "[\"$b\",\"$o\"]" ] || fail "Needs you after shut $c is not the other two cards"
  [ -s "$ST/kept/$c/$c.patch" ] && [ "$(git -C "$R" rev-parse hand/one)" = "$tip" ] || fail "shut lost the kept patch of $c, or moved its branch"
}

# A reopened issue is given back by a turn only when its newest card was shut (#599). Bugs: an open issue whose card
# landed is given back (its lines moved, a new card picked: its work is on main); a shut card whose process is still
# ending is given back before that process ends (it would write a blocked line after its lines moved, and lose its
# change); once it has ended, the shut card is still not given back.
t_reopenonly() {
  local p t open
  setup "$(jq -cs . <(issue 5 2026-01-01) <(issue 6 2026-02-01))"; mkdir -p "$ST"; open=$(cat "$STUB/issues.json")
  sleep 60 & p=$!; t=$(. "$SRC/lib/portable.sh"; p_started "$p") # sleep: a stand-in for the shut card's process, still ending
  { landed 5
    jq -cn --argjson p "$p" --arg t "$t" '{card:"c0-6",issue:6,time:"2026-11-01T00:00:00Z",tokens:{claude:0,codex:0},result:"ok",sha:"",reason:""}
      | (. + {step:"picked"}), (. + {step:"worktree",pid:$p,started:$t}), (. + {step:"blocked",result:"blocked",reason:"NO-GO"}),
        (. + {step:"closed",reason:"the issue was closed by hand while the card was blocked"})'; } > "$ST/cards.jsonl"
  loop check || fail "the fixture does not check"; before=$(cat "$ST/cards.jsonl")
  fx_in "reopened '$open'"
  [ "$(cat "$ST/cards.jsonl")" = "$before" ] && [ ! -s "$ST/retried.jsonl" ] || fail "a turn moved lines of the landed #5 or of #6 while its card's process ran: $(cat "$ST/retried.jsonl" 2>/dev/null)"
  kill "$p"; wait "$p" 2>/dev/null; fx_in "reopened '$open'"
  [ "$(jq -r .card "$ST/retried.jsonl" | sort -u)" = c0-6 ] || fail "once its process ended, #6's shut card alone was not given back (exit $RC): $(cat "$ST/retried.jsonl" 2>/dev/null)"
  [ "$(st '"\(.issue) \(.step)"')" = '5 landed' ] || fail "the landed #5 lost its lines, or #6's stayed: $(st '"\(.issue) \(.step)"' | tr '\n' ',')"
}

# Bugs: a card whose issue is already fixed on main is blocked for leaving no change, and the issue stays
# open; the brief does not ask for the ALREADY-DONE line; the session's word alone closes an issue, or closes it
# over the reviewer's NO-GO; a session that left no change and no such line (or one that is not its last line) is
# reviewed or closed instead of blocked; the report lists a closed card as open, or the dashboard does not count it;
# the reviewer reads the main the session started from, not today's; a GO closes the issue although main moved
# during that review (another card may have removed the fix); the closed line has no waitSec, so the drift watch
# (bench/drift.sh) leaves the closed card out of its mean wait.
# The cards' steps after a session that changed nothing are called as card() calls them: nochange() (the reply's last
# line, the review of an ALREADY-DONE line, the block), and closed() under the lock (main moved during the review).
# donewt <issue> <reply>...: a fresh main with those issues, a picked line of card c0-<issue> of each and its worktree on
# main, cards/c0-<issue>, beside which its session, which changed nothing, left the reply (its .out, and an empty .err);
# the reviewer's prompt is kept in $STUB/asked; head is main's commit.
donewt() {
  local s='' n
  for ((n = 1; n < $#; n += 2)); do s+="$(issue "${!n}" 2026-01-01),"; done
  setup "[${s%,}]"; mkdir -p "$ST" "$T/$CASE/cards"; head=$(git -C "$R" rev-parse HEAD)
  while [ $# -gt 1 ]; do
    landed "$1" | jq -c '.step = "picked" | .sha = "" | .title = "title \(.issue)" | del(.product)' >> "$ST/cards.jsonl"
    git -C "$R" worktree add -q --detach "$T/$CASE/cards/c0-$1" || fail "the worktree of c0-$1"
    jq -cn --arg r "$2" '{type: "result", is_error: false, result: $r}' > "$T/$CASE/cards/c0-$1.out" && : > "$T/$CASE/cards/c0-$1.err"
    shift 2
  done
  sed -i 's|^cat > /dev/null; echo x|cat > "$STUB/asked"; echo x|' "$STUB/codex"
}
DONE='ALREADY-DONE: a.txt already holds the word one'
# Main moves after the session began: the reviewer reads the new main, not the one the session started from. The
# brief is the card's own (brief()), and the card has waited 4 s on other cards (waitsec, as card() keeps it).
t_done() {
  donewt 7 $'I looked.\n\n'"$DONE"$'\n'; echo "$GO" > "$STUB/review.1"
  git -C "$R" commit -q --allow-empty -m "landed during the session"; head=$(git -C "$R" rev-parse HEAD)
  echo 'git rev-parse HEAD > "$STUB/reviewed"' > "$STUB/review-cmd"
  fx_in 'cd "$R" && waitsec=4 && b=$(brief c0-7 "$(gh issue view 7 --json number,title,body,labels,milestone)" "$(header)") && nochange c0-7 7 "$CONVEYOR_CARDS/c0-7" "$b"'
  [ "$RC" = 0 ] || fail "nochange exited $RC: $(cat "$T/$CASE/run.out")"
  grep -q 'ALREADY-DONE: <where it is fixed' "$STUB/asked" || fail "the brief does not ask for the ALREADY-DONE line"
  grep -q 'changed nothing' "$STUB/asked" && grep -q '# Issue #7:' "$STUB/asked" && [ "$(tail -n 1 "$STUB/asked")" = "$DONE" ] \
    && ! grep -q 'git diff --cached' "$STUB/asked" || fail "the reviewer was not asked to confirm the issue and the ALREADY-DONE line: $(cat "$STUB/asked")"
  [ "$(cat "$STUB/reviewed")" = "$head" ] || fail "the reviewer did not read main as it stood when the review started"
  [ "$(st '.step' | tr '\n' ' ')" = "picked start review closed " ] || fail "steps of a card whose issue is already fixed: $(st '.step' | tr '\n' ' ')"
  [ "$(st 'select(.step == "closed") | [.result, .sha, .reason] | join("|")')" = "ok||$DONE" ] || fail "closed line: $(st 'select(.step == "closed")')"
  [ "$(st 'select(.step == "closed") | .waitSec')" = 4 ] || fail "the closed line does not carry the card's wait: $(st 'select(.step == "closed")')"
  [ "$(cat "$STUB/closed")" = 7 ] && grep -qF "$DONE" "$STUB/close-comments" || fail "issue #7 was not closed with the ALREADY-DONE line: $(cat "$STUB/close-comments" 2>&1)"
  [ "$(git -C "$R" rev-parse HEAD)" = "$head" ] && [ -z "$(git -C "$R" status --porcelain)" ] && [ -z "$(ls "$T/$CASE/cards")" ] || fail "something was committed, or main is dirty, or the worktree is left: $(ls "$T/$CASE/cards")"
  loop check || fail "the record check refuses a closed line"
  [ "$(loop cards | jq -c '[.landed, .blocked, .open, .cards[0].step]')" = '[1,0,0,"closed"]' ] || fail "a closed card is not counted like a landed one: $(loop cards)"
  out=$(CONVEYOR_MAIN=$R bash "$SRC/report.sh") || fail "report exited non-zero"
  grep -Eq '^cards landed +1$' <<<"$out" && ! grep -q '^open ' <<<"$out" || fail "the report does not count a closed card like a landed one: $out"
  ! loop retry 7 >/dev/null 2>&1 || fail "retry took back a card that closed its issue"
}

# The reviewer disagrees: blocked, its findings posted, the issue left open.
t_donenogo() {
  donewt 8 "$DONE"; echo "$NOGO" > "$STUB/review.1"
  fx_in 'cd "$R" && nochange c0-8 8 "$CONVEYOR_CARDS/c0-8" "the brief of # Issue #8:"'
  [ "$RC" = 0 ] || fail "nochange exited $RC: $(cat "$T/$CASE/run.out")"
  # Bug (#495): the reason said the kept folder holds the session's errors, but the review writes its own in their place.
  local c=c0-8
  st 'select(.issue == 8 and .step == "blocked") | .reason' | grep -qF "the issue asks. Its session's output and the last error output (of its review, when the review started) are kept in kept/$c/. ALREADY-DONE: a.txt already" || fail "a NO-GO on ALREADY-DONE does not say the kept errors are the review's: $(st 'select(.issue == 8 and .step == "blocked") | .reason')"
  st 'select(.issue == 8 and .step == "blocked") | .reason' | grep -q 'reviewer says that main does not do what the issue asks.*ALREADY-DONE: a.txt already' || fail "a NO-GO on ALREADY-DONE did not block with the reason: $(st 'select(.issue == 8) | "\(.step) \(.reason)"')"
  [ "$(st 'select(.issue == 8 and .step == "review") | .result')" = NO-GO ] && grep -q '^8 --body .*blocked' "$STUB/comments" && grep -q 'wrong word' "$STUB/comments" || fail "the disagreeing review is not recorded or not posted on the issue"
  [ ! -e "$STUB/closed" ] && [ "$(wc -l < "$STUB/reviews")" = 1 ] || fail "issue #8 was closed over a NO-GO, or it got a second review"
}

# Issue 1105: a card whose issue's work is done outside the repository (judge records written, issues filed) changes
# no tracked file. Bug it catches: such a card blocked with "the session made no change" although it did the work, and
# its issue stayed open; or it closed on the session's word alone, with no review of the evidence its line names.
# Also: a Codex (or OpenCode) build's line was not read, as its stream has no Claude result, so the card blocked; the
# reviewer was not given the issues and state files the line names, which a Claude or OpenCode reviewer, with no
# shell, web or folder outside the worktree, cannot read itself; the issues inside a range were not given, nor the
# session's records when older files and session logs used up the limit first.
OUT='DONE-OUTSIDE: 3 judge records in conveyor/state/testactions/, issues #21 to #23 filed'
t_doneoutside() {
  donewt 14 ''; echo "$GO" > "$STUB/review.1"
  jq -cn --arg r $'I judged 3 files and filed 3 issues.\n\n'"$OUT" '{type: "item.completed", item: {type: "agent_message", text: $r}}' > "$T/$CASE/cards/c0-14.out"
  jq -c --argjson a "[$(issue 21 2026-01-01)]" '. + $a' "$STUB/issues.json" > "$STUB/i.new" && mv "$STUB/i.new" "$STUB/issues.json"
  # Older records that sort first by name and fill the limit, then the session's start, a long session log and the
  # session's own record: the record must still reach the reviewer, and the range must give #22 as well.
  mkdir -p "$ST/testactions" && for i in 0 1 2 3 4 5 6 7 8 9 10 11; do head -c 4000 /dev/zero | tr '\0' o > "$ST/testactions/0old$i"; done
  touch -t 202601010000 "$ST/testactions"/0old* && : > "$T/$CASE/cards/c0-14.before"
  head -c 50000 /dev/zero | tr '\0' e > "$ST/testactions/1.events" && echo '{"verdict": "rewrite a.test.sh"}' > "$ST/testactions/z1"
  fx_in 'cd "$R" && waitsec=2 && nochange c0-14 14 "$CONVEYOR_CARDS/c0-14" "the brief of # Issue #14:"'
  [ "$RC" = 0 ] || fail "nochange exited $RC: $(cat "$T/$CASE/run.out")"
  grep -qF 'did the work outside the repository' "$STUB/asked" && grep -qF 'Done-when line' "$STUB/asked" && [ "$(tail -n 1 "$STUB/asked")" = "$OUT" ] \
    || fail "the reviewer was not asked to check the evidence the DONE-OUTSIDE line names: $(cat "$STUB/asked")"
  grep -qF 'body of 21' "$STUB/asked" && grep -A1 -F '## Issue #22' "$STUB/asked" | grep -qF 'GitHub did not give this issue.' \
    && grep -qF '## Issue #23' "$STUB/asked" && grep -A1 -F '## conveyor/state/testactions/z1' "$STUB/asked" | grep -qF 'rewrite a.test.sh' && ! grep -qF '## Issue #14' "$STUB/asked" \
    && grep -qE 'left out [0-9]+ more files of conveyor/state/testactions/' "$STUB/asked" \
    || fail "the reviewer was not given the issues and state files the line names: $(cat "$STUB/asked")"
  [ "$(st '.step' | tr '\n' ' ')" = "picked start review closed " ] || fail "steps of a card whose work was done outside the repository: $(st '.step' | tr '\n' ' ')"
  [ "$(st 'select(.step == "closed") | [.result, .reason] | join("|")')" = "ok|Done outside the repository: $OUT" ] || fail "closed line: $(st 'select(.step == "closed")')"
  [ "$(cat "$STUB/closed" 2>&1)" = 14 ] && grep -qF 'I judged 3 files and filed 3 issues.' "$STUB/close-comments" && grep -qF "$OUT" "$STUB/close-comments" \
    || fail "issue #14 was not closed with the session's report: $(cat "$STUB/close-comments" 2>&1)"
  [ -z "$(ls "$T/$CASE/cards")" ] && [ "$(git -C "$R" rev-parse HEAD)" = "$head" ] || fail "something was committed, or the worktree is left: $(ls "$T/$CASE/cards")"
}

# #1444 (R251). Bug it catches: an OpenCode build that wrote its report and its DONE-OUTSIDE line as two text parts of
# its last step had only the last part read as its reply (lastreply()), so the issue was closed with the DONE-OUTSIDE
# line alone as its comment, and the report was lost.
t_doneoutsideparts() {
  donewt 16 ''; echo "$GO" > "$STUB/review.1"
  { echo '{"type":"step_start","part":{}}'; jq -cn '{type: "text", part: {text: "I judged 3 files and filed 3 issues."}}'
    jq -cn --arg o "$OUT" '{type: "text", part: {text: $o}}'; echo '{"type":"step_finish","part":{}}'; } > "$T/$CASE/cards/c0-16.out"
  fx_in 'cd "$R" && nochange c0-16 16 "$CONVEYOR_CARDS/c0-16" "the brief of # Issue #16:"'
  [ "$RC" = 0 ] && [ "$(cat "$STUB/closed" 2>&1)" = 16 ] || fail "nochange did not close #16 ($RC): $(cat "$T/$CASE/run.out") $(st '"\(.step) \(.reason)"')"
  grep -qF 'I judged 3 files and filed 3 issues.' "$STUB/close-comments" && grep -qF "$OUT" "$STUB/close-comments" \
    || fail "the closing comment of a two-part OpenCode reply does not hold both parts: $(cat "$STUB/close-comments" 2>&1)"
}

# The reviewer finds the evidence short: blocked, the reason giving the reviewer's finding, the issue left open.
t_doneoutsidenogo() {
  donewt 15 "$OUT"; echo "$NOGO" > "$STUB/review.1"
  fx_in 'cd "$R" && nochange c0-15 15 "$CONVEYOR_CARDS/c0-15" "the brief of # Issue #15:"'
  [ "$RC" = 0 ] || fail "nochange exited $RC: $(cat "$T/$CASE/run.out")"
  st 'select(.issue == 15 and .step == "blocked") | .reason' | grep -qF "the session made no change and said that it did the issue's work outside the repository. The reviewer says that the evidence does not show the issue's work done: [P1] a.txt:1 wrong word. Its session's output" \
    || fail "a NO-GO on DONE-OUTSIDE did not block with the reviewer's reason: $(st 'select(.issue == 15) | "\(.step) \(.reason)"')"
  [ ! -e "$STUB/closed" ] && [ -z "$(st 'select(.issue == 15 and .step == "closed")')" ] || fail "issue #15 was closed over a NO-GO"
}

# Bug (#1144): a DONE-OUTSIDE line that names a big folder and then a file gave the folder all 40000 characters, so
# the reviewer never saw the file (the hold in control.json a Done-when line cites) and could not confirm the work.
# The folder still gets all the file leaves: ten of its twelve 4000-character records (nine whole, one cut), not a
# share that cuts records the reviewer also needs.
t_doneoutsidepaths() {
  setup '[]'; mkdir -p "$ST/testactions"
  for i in 0 1 2 3 4 5 6 7 8 9 10 11; do head -c 4000 /dev/zero | tr '\0' o > "$ST/testactions/r$i"; done
  echo '{"hold": {"781": "held by the judge"}}' > "$ST/control.json"
  fx_in 'outsidefacts "DONE-OUTSIDE: records in conveyor/state/testactions/, the hold in conveyor/state/control.json" 1144'
  [ "$RC" = 0 ] || fail "outsidefacts exited $RC: $(head -c 400 "$T/$CASE/run.out")"
  grep -A1 -F '## conveyor/state/control.json' "$T/$CASE/run.out" | grep -qF 'held by the judge' \
    || fail "the file named after a big folder did not reach the reviewer: $(grep -F 'left out' "$T/$CASE/run.out")"
  grep -qF 'left out 2 more files of conveyor/state/testactions/' "$T/$CASE/run.out" && [ "$(grep -c '^## conveyor/state/testactions/' "$T/$CASE/run.out")" = 10 ] \
    || fail "the big folder did not get all the file left of the limit: $(grep -c '^## conveyor/state/testactions/' "$T/$CASE/run.out") records, $(grep -F 'left out' "$T/$CASE/run.out")"
}

# closed() on card c0-<issue>'s worktree, at main's commit h as the reviewer read it, after main moved to m by
# <move> during the review. Its exit is in $RC, the reason it prints in run.out.
donemove() { # <issue> <move>
  donewt "$1" "$DONE"
  (cd "$R" && eval "$2") && [ "$(git -C "$R" rev-parse HEAD)" != "$head" ] || fail "main did not move during the review"
  fx_in "cd \"\$R\" && locked closed c0-$1 $1 \"\$CONVEYOR_CARDS/c0-$1\" '$DONE'"
}
# Main moves during the review and replaces the word one in a.txt, the line the ALREADY-DONE line cites, so the fix
# is gone: closed() refuses, saying why, and the issue stays open.
t_donemoved() {
  donemove 11 'echo two > a.txt && git commit -qam "landed during the review"'
  [ "$RC" = 1 ] && grep -q '^the reviewer confirmed that main already fixes the issue, but main changed during that review' "$T/$CASE/run.out" \
    || fail "a GO for a main that moved and changed a.txt was not refused with the reason (exit $RC): $(cat "$T/$CASE/run.out")"
  [ ! -e "$STUB/closed" ] && [ -z "$(st 'select(.issue == 11 and .step == "closed")')" ] || fail "issue #11 was closed although main moved during the review"
}

# Bug (#552): main moved during the review but left a.txt, the file the ALREADY-DONE line names, as it was; the card
# was blocked anyway, and on a busy belt every retry's review met another move. The engine checks the named file
# against the new main and closes the issue.
t_donemovedkept() {
  donemove 12 'echo other > other.txt && git add other.txt && git commit -qm "landed during the review"'
  [ "$RC" = 0 ] && [ ! -s "$T/$CASE/run.out" ] || fail "closed() refused although main kept a.txt (exit $RC): $(cat "$T/$CASE/run.out")"
  [ "$(cat "$STUB/closed" 2>&1)" = 12 ] && grep -qF "$DONE" "$STUB/close-comments" && [ "$(st 'select(.issue == 12 and .step == "closed") | [.result, .reason] | join("|")')" = "ok|$DONE" ] \
    || fail "issue #12 was not closed although main kept a.txt: $(st 'select(.issue == 12) | "\(.step) \(.reason)"')"
}

# t_donemoved calls closed() alone; this runs the card's step, nochange(), whose reviewer moves main and replaces
# a.txt, the file the line cites. Bug: closed()'s refusal is lost in nochange() (lib/followups.sh), so the issue is
# closed, or the card is left with no blocked line, or one that does not say why.
t_donereviewmoved() {
  donewt 13 "$DONE"; echo "$GO" > "$STUB/review.1"
  echo '(cd "$R" && echo two > a.txt && git commit -qam "landed during the review")' > "$STUB/review-cmd"
  fx_in 'cd "$R" && nochange c0-13 13 "$CONVEYOR_CARDS/c0-13" "the brief of # Issue #13:"'
  [ "$RC" = 0 ] && [ "$(git -C "$R" show HEAD:a.txt)" = two ] || fail "nochange exited $RC, or main did not move during the review: $(cat "$T/$CASE/run.out")"
  st 'select(.issue == 13 and .step == "blocked") | .reason' | grep -qF "but main changed during that review. The fix is possibly not on main now, so the engine did not close the issue. Its session's output" \
    && st 'select(.issue == 13 and .step == "blocked") | .reason' | grep -qF "$DONE" || fail "the card was not blocked with closed()'s reason: $(st 'select(.issue == 13) | "\(.step) \(.reason)"')"
  [ ! -e "$STUB/closed" ] && [ -z "$(st 'select(.issue == 13 and .step == "closed")')" ] || fail "issue #13 was closed although the cited a.txt changed during the review"
}

# No change and no ALREADY-DONE last line (#9 says it, but not last; #10 does not say it): blocked as before, with no review.
# Bug (#495): the reason did not say what the session replied or where its output and errors are kept, so the owner
# could not tell why it stopped. It quotes the last reply, on one line, and names the kept folder, which holds both.
t_doneempty() {
  donewt 9 $'ALREADY-DONE: a.txt holds it\nI changed nothing.' 10 $'I looked.\n\nI could not find the file named in the issue'
  local c r said n
  fx_in 'cd "$R" && nochange c0-9 9 "$CONVEYOR_CARDS/c0-9" brief && nochange c0-10 10 "$CONVEYOR_CARDS/c0-10" brief'
  [ "$RC" = 0 ] || fail "nochange exited $RC: $(cat "$T/$CASE/run.out")"
  for n in 9 10; do
    c=c0-$n; r=$(st "select(.issue == $n and .step == \"blocked\") | .reason")
    case $n in 9) said='ALREADY-DONE: a.txt holds it I changed nothing.' ;; 10) said='I looked. I could not find the file named in the issue' ;; esac
    [ "$r" = "the session made no change, so there is nothing to review. Its session's output and errors are kept in kept/$c/. Its last reply: $said" ] \
      || fail "issue $n: no change and no ALREADY-DONE last line was not blocked with its reply and kept folder: $r"
    [ -s "$ST/kept/$c/$c.out" ] && [ -e "$ST/kept/$c/$c.err" ] && [ ! -e "$T/$CASE/cards/$c.out" ] || fail "issue $n: the session's output and errors are not in kept/$c/: $(ls "$ST/kept/$c" 2>&1)"
    # Bug: with no findings and no patch, block() did not post the reason, so the issue did not say where the logs are.
    grep -qF "$n --body Conveyor card $c is blocked: $r" "$STUB/comments" || fail "issue $n: the reason naming its kept folder was not posted on the issue: $(cat "$STUB/comments" 2>&1)"
  done
  [ ! -e "$STUB/reviews" ] && [ ! -e "$STUB/closed" ] && [ "$(git -C "$R" rev-parse HEAD)" = "$head" ] || fail "a card with no change and no ALREADY-DONE line was reviewed, closed or landed"
}
