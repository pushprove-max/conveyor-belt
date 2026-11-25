#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: a main-red fix card whose session made no change while its cases do not all pass on main closes when newer
# fix cards took its work over (bugproof.sh redreplaced(), called by followups.sh nochange()). Its cases call
# mainredproof.test.sh's redsetup() and mainred.test.sh's eng().
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# redsetup's fixture, both cases failing on main unless <ok.txt on main> names one, its entry's fix card cfix, and
# cfix's worktree on main. Each <entry> ({sha, cases, card}) goes into the main-red record, before cfix's entry when its
# sha is `old`, else after it; each <card line> ({card, step}) into the card records.
replfix() { # <entries json array> <card lines json array> [<ok.txt on main>]
  redsetup "${3:-}"
  jq -c --argjson e "$1" '.reds[0].card = "cfix" | .reds = [$e[] | select(.sha == "old")] + .reds + [$e[] | select(.sha != "old")]' \
    "$ST/mainred.json" > "$STUB/red.new" && mv "$STUB/red.new" "$ST/mainred.json" \
    && jq -c '.[] | {issue: 0, time: "2026-01-01T00:00:00Z", tokens: {claude: 0, codex: 0}, result: "ok", sha: "", reason: ""} + .' <<<"$2" >> "$ST/cards.jsonl" \
    && git -C "$R" worktree add -q --detach "$T/$CASE/cards/cfix" HEAD || fail "the fixture could not be made"
}

# Issue 1666. Bug it catches: a fix card whose session made no change was blocked under Needs you while newer fix cards
# on the belt already held each of its failing cases, cnew1 (`a.test: one`, building) and cnew2 (`c.test`, picked), so
# it stayed there until a person shut it. It closes, its closed line and the log naming the cards that took it over and
# what its run on main showed; it is not blocked, its worktree goes, and its entry holds main red no more.
t_mainredreplaced() {
  replfix '[{"sha": "new1", "cases": [{"case": "a.test: one", "file": "a.test"}], "card": "cnew1"},
    {"sha": "new2", "cases": [{"case": "c.test", "file": "c.test"}], "card": "cnew2"}]' \
    '[{"card": "cnew1", "step": "picked"}, {"card": "cnew1", "step": "build", "time": "2026-01-02T00:00:00Z"},
      {"card": "cnew2", "step": "picked"}]'
  local s out r
  s=$(git -C "$R" rev-parse HEAD)
  out=$(eng 'nochange cfix 0 "$CONVEYOR_CARDS/cfix" brief; redopen cfix && echo STILLOPEN' 2>&1)
  r="Replaced: newer main-red fix cards hold each of its cases, on the belt or landed for a case that passes on main: cnew1, cnew2. The session made no change, so there is nothing to review. Its cases on main as it is now: \`a.test: one\`, \`c.test\` still fails on main's code at $s, and there is no change to run them with."
  [ "$(st 'select(.card == "cfix" and .step == "closed") | .reason')" = "$r" ] && [[ $out == *"conveyor: card cfix closed: $r"* ]] \
    || fail "nochange on cfix (cases held by cnew1 and cnew2 on the belt) did not close it naming them, or did not log it: $out: $(st 'select(.card == "cfix") | "\(.step) \(.reason)"' | tr '\n' ,)"
  [ -z "$(st 'select(.card == "cfix" and .step == "blocked")')" ] && [[ $out != *STILLOPEN* ]] && [ ! -e "$T/$CASE/cards/cfix" ] \
    || fail "nochange on cfix (cases held by cnew1 and cnew2) blocked it, left its entry open or kept its worktree: $out"
  recok "$ST/cards.jsonl" "the replaced fix card"
}

# replfix's fixture with `a.test: one` passing on main and held by cnew1, landed, and `c.test` failing there and held by
# cnew2, on the belt.
repllanded() {
  replfix '[{"sha": "new1", "cases": [{"case": "a.test: one", "file": "a.test"}], "card": "cnew1"},
    {"sha": "new2", "cases": [{"case": "c.test", "file": "c.test"}], "card": "cnew2"}]' \
    '[{"card": "cnew1", "step": "picked"}, {"card": "cnew1", "step": "landed", "sha": "abc1234", "product": true},
      {"card": "cnew2", "step": "picked"}]' one
}

# Issue 1666. Bug it catches: a landed newer card never counted, so cfix was blocked though cnew1 landed holding
# `a.test: one`, which now passes on main in each of FULL_ALONE runs, and cnew2, on the belt, holds `c.test`, which
# still fails there. It closes, naming both.
t_mainredreplacedlanded() {
  repllanded
  local out r
  out=$(eng 'nochange cfix 0 "$CONVEYOR_CARDS/cfix" brief' 2>&1)
  r=$(st 'select(.card == "cfix" and .step == "closed") | .reason')
  [[ $r == "Replaced: newer main-red fix cards hold each of its cases, on the belt or landed for a case that passes on main: cnew1, cnew2. "*'`a.test: one` passes on main'* ]] \
    && [ -z "$(st 'select(.card == "cfix" and .step == "blocked")')" ] \
    || fail "nochange on cfix (a.test: one passes on main, held by cnew1 landed; c.test fails, held by cnew2 on the belt) did not close it naming both: $out: $(st 'select(.card == "cfix") | "\(.step) \(.reason)"' | tr '\n' ,)"
}

# Issue 1666. Bug it catches: one pass counted as proof that a landed card fixed a case, though main is no longer red
# for a case only when it passes in each of FULL_ALONE runs (bugproof.sh redproof()). `a.test: one` passes in its first
# two runs and fails in its third; `c.test` fails in the first, which stopped the runs after one. cnew1 landed holding
# `a.test: one` then counted, and cfix closed. Now `a.test: one` runs alone until its third run, and cfix is blocked.
t_mainredreplacedflaky() {
  repllanded
  local out
  printf '%s\n' '[ "${CONVEYOR_TEST_FILE:-}" = a.test ] && { n=$(($(cat "$STUB/n" 2>/dev/null || echo 0) + 1)); echo $n > "$STUB/n"; [ $n != 3 ] || { grep -vx one ok.txt > ok.new; mv ok.new ok.txt; }; }' \
    | cat - "$STUB/mainrun-cmd" > "$STUB/mainrun-cmd.new" && mv "$STUB/mainrun-cmd.new" "$STUB/mainrun-cmd" || fail "the flaky runner could not be made"
  out=$(eng 'nochange cfix 0 "$CONVEYOR_CARDS/cfix" brief' 2>&1)
  [ "$(cat "$STUB/n" 2>/dev/null)" = 3 ] && [ -n "$(st 'select(.card == "cfix" and .step == "blocked")')" ] \
    && [ -z "$(st 'select(.card == "cfix" and .step == "closed")')" ] \
    || fail "nochange on cfix (a.test: one, held by cnew1 landed, fails in its third run; c.test fails, held by cnew2 on the belt) closed it, or did not run a.test three times (runs: $(cat "$STUB/n" 2>/dev/null)): $out: $(st 'select(.card == "cfix") | "\(.step) \(.reason)"' | tr '\n' ,)"
}

# Issue 1666, what must stay true: a landed card counts for a case only on passes of main as it is when the closed line
# is written. The other writer: a landing (claim.sh land()), which moves main without the locks redreplaced() takes. It
# is made to act at the weak point, after redproof()'s runs and before redreplaced(), as a commit on main that breaks
# `a.test: one`: the main-red check reads only main's branch, so a whole card's landing would prove no more. Bug it
# catches: the passes on the older commit still let cnew1, landed, count for `a.test: one`, so cfix closed while main
# failed the case again. It is blocked.
t_mainredreplacedmoved() {
  repllanded
  local out
  out=$(eng 'eval "real$(declare -f redproof)"
    redproof() { local rc=0; realredproof "$@" || rc=$?; (printf "two\n" > "$R/ok.txt" && git -C "$R" commit -qam "break a.test: one") >&2; return $rc; }
    nochange cfix 0 "$CONVEYOR_CARDS/cfix" brief' 2>&1)
  [ -n "$(st 'select(.card == "cfix" and .step == "blocked")')" ] && [ -z "$(st 'select(.card == "cfix" and .step == "closed")')" ] \
    || fail "nochange on cfix (a.test: one passed on main, held by cnew1 landed; main moved to a commit breaking it after the runs; c.test held by cnew2 on the belt) closed it: $out: $(st 'select(.card == "cfix") | "\(.step) \(.reason)"' | tr '\n' ,)"
}

# Issue 1666. Bug it catches: a card whose landing clashed, and whose one rebuild made no change, holds its reviewed
# change in <worktree>.patch and .base (cardland.sh landconflict()); closing it as replaced deleted them with the
# worktree. It is blocked as before, with that change kept in its kept folder, though cnew1 on the belt holds its cases.
t_mainredreplacedpatch() {
  replfix '[{"sha": "new1", "cases": [{"case": "a.test: one", "file": "a.test"}, {"case": "c.test", "file": "c.test"}], "card": "cnew1"}]' \
    '[{"card": "cnew1", "step": "picked"}]'
  local w=$T/$CASE/cards/cfix out
  printf 'one\n' > "$w/ok.txt" && git -C "$w" add ok.txt && git -C "$w" diff --cached --binary > "$w.patch" && git -C "$w" rev-parse HEAD > "$w.base" \
    && git -C "$w" reset -q --hard || fail "the reviewed change could not be made"
  out=$(eng 'nochange cfix 0 "$CONVEYOR_CARDS/cfix" brief' 2>&1)
  [ -n "$(st 'select(.card == "cfix" and .step == "blocked")')" ] && [ -z "$(st 'select(.card == "cfix" and .step == "closed")')" ] \
    && grep -qx '+one' "$ST/kept/cfix/cfix.patch" 2>/dev/null && [ -s "$ST/kept/cfix/cfix.base" ] \
    || fail "nochange on cfix (a reviewed change in cfix.patch; cnew1 on the belt holds its cases) closed it, or did not keep that change in kept/cfix: $out: $(st 'select(.card == "cfix") | "\(.step) \(.reason)"' | tr '\n' ,)"
}

# Issue 1666, what must stay true: the card closes as replaced only while newer cards on the belt hold every case its
# entry holds when the closed line is written. The other writers: mainred(), which adds a case found failing on cfix's
# commit to cfix's entry, and the taker cnew1's own blocked line (record(), as block() writes it). Each is made to act
# at the weak point, after redtakers() read the records and before the closed line, taking its lock without waiting (a
# wait there would never end, as this shell holds it). Bugs it catches: redreplaced() read the takers or wrote the line
# without the main-red record's lock, so `b.test: two` joined cfix's entry, which no newer card holds, and the closed
# line ended its hold on the case; or without the card records' lock (followups.sh nochange(): locked), so cnew1 was
# blocked while cfix closed naming it as the card on the belt, and no card on the belt held the cases.
t_mainredreplacedjoin() {
  replfix '[{"sha": "new1", "cases": [{"case": "a.test: one", "file": "a.test"}, {"case": "c.test", "file": "c.test"}], "card": "cnew1"}]' \
    '[{"card": "cnew1", "step": "picked"}]'
  local s out
  s=$(git -C "$R" rev-parse HEAD)
  out=$(eng 'eval "real$(declare -f redtakers)"
    redtakers() { local rc=0; realredtakers "$@" || rc=$?; (flock() { command flock -n "$@"; }; mainred c9 "b.test: two" b.test '"$s"'
      record cnew1 0 blocked blocked "{\"reason\": \"build: it failed\"}") >&2; return $rc; }
    nochange cfix 0 "$CONVEYOR_CARDS/cfix" brief' 2>&1)
  [ -n "$(st 'select(.card == "cfix" and .step == "closed")')" ] && [[ $out == *"the main-is-red record could not be locked; b.test: two goes to no fix card"* ]] \
    && ! jq -e 'any(.reds[].cases[]; .case == "b.test: two")' "$ST/mainred.json" >/dev/null \
    && [[ $out == *"conveyor: cannot record cnew1 blocked"* ]] && [ -z "$(st 'select(.card == "cnew1" and .step == "blocked")')" ] \
    || fail "nochange on cfix (cnew1 holds its cases; after the takers were read, mainred() adds b.test: two to its entry and cnew1 writes its blocked line) let the case join or cnew1 block while the card closed, or did not close it: $out: $(st 'select(.card == "cfix") | "\(.step) \(.reason)"' | tr '\n' ,)"
}

# Issue 1666. Bug it catches: a fix card was closed as replaced though no newer card on the belt holds each of its
# cases: cold, on the belt with both, has the entry before cfix's (older, not newer); cblk, after it with both, is
# blocked; cpart, after it and on the belt, holds `a.test: one` alone; clnd, after it with both, landed, and yet both
# still fail on main (its fix did not hold, or a later commit broke them again and they stayed with cfix): closing cfix
# would leave them with no fix card. Each alone would close it if its check were missing.
# It is blocked for the owner as before, with the reason of its run on main, and not closed.
t_mainrednotreplaced() {
  replfix '[{"sha": "old", "cases": [{"case": "a.test: one", "file": "a.test"}, {"case": "c.test", "file": "c.test"}], "card": "cold"},
    {"sha": "new1", "cases": [{"case": "a.test: one", "file": "a.test"}, {"case": "c.test", "file": "c.test"}], "card": "cblk"},
    {"sha": "new2", "cases": [{"case": "a.test: one", "file": "a.test"}], "card": "cpart"},
    {"sha": "new3", "cases": [{"case": "a.test: one", "file": "a.test"}, {"case": "c.test", "file": "c.test"}], "card": "clnd"}]' \
    '[{"card": "cold", "step": "picked"}, {"card": "cblk", "step": "picked"}, {"card": "cblk", "step": "blocked", "result": "blocked", "reason": "build: it failed"},
      {"card": "cpart", "step": "picked"}, {"card": "clnd", "step": "picked"}, {"card": "clnd", "step": "build", "time": "2026-01-02T00:00:00Z"},
      {"card": "clnd", "step": "landed", "sha": "abc1234", "product": true}]'
  local out
  out=$(eng 'nochange cfix 0 "$CONVEYOR_CARDS/cfix" brief' 2>&1)
  [[ $(st 'select(.card == "cfix" and .step == "blocked") | .reason') == "the session made no change, so there is nothing to review. Its cases on main as it is now: "*'still fails on main'"'"'s code at '*', and there is no change to run them with.'* ]] \
    && [ -z "$(st 'select(.card == "cfix" and .step == "closed")')" ] \
    || fail "nochange on cfix (no newer card on the belt holding every case: cold older, cblk blocked, cpart with a.test: one alone, clnd landed) closed it, or did not block it: $out: $(st 'select(.card == "cfix") | "\(.step) \(.reason)"' | tr '\n' ,)"
}
