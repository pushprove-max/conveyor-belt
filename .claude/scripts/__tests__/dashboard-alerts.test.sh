#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 60
# The Board's cache-write alert (dashboard_alerts.jq) over the limit's 24 h cache writes, by card, session and model
# (cacheWrites24h.cards), and the Metrics steps that put each session to its card's step: it names the card steps that
# wrote the most cache in its 24 h, largest first, up to five, and the writes no card step accounts for as one line.
# Bug caught: an alert that only said "find the sessions rewriting cache", so the owner searched the card records by hand.
set -euo pipefail
SOURCE=$(git rev-parse --show-toplevel)
fail() { echo "FAIL: $*" >&2; exit 1; }
NOW=$(jq -n '"2026-11-19T12:00:00Z" | fromdate')
# alert <cacheWritePct24h> [<cacheWrites24h.cards> [<metrics.steps>]]: the cache-write alert's text over the fixture,
# or nothing with no such alert.
alert() {
  jq -rn --argjson now "$NOW" --argjson srcs '[]' --argjson preva '[{}]' \
    --argjson parts "$(jq -cn --argjson pct "$1" --argjson cards "${2:-null}" --argjson steps "${3:-null}" '
      # A session of <card> and <model> that wrote <w5>+<w1> from <first> to <last> (times of 2026-11-19, else whole).
      def t: if test("T") then . else "2026-11-19T\(.)Z" end | fromdate;
      def s($card; $m; $first; $last; $w5; $w1): {card: $card, model: $m, first: ($first | t), last: ($last | t), write: $w5, write1h: $w1};
      [{limit: {cacheWritePct24h: $pct, cacheWrites24h: {write: 9000, write1h: 4000, cards: ($cards // [
          s("c20261118T200000-beta-22"; "claude-sonnet-5-5"; "10:30:00"; "10:59:00"; 500; 2500),
          # A build whose last request was 0.4 s past the second its build line names (a line keeps whole seconds).
          # Bug caught: the writes put to the next step, alpha#11 review.
          (s("c20261119T090000-alpha-11"; "claude-opus-5-5"; "09:30:00"; "10:00:00"; 3000; 1000) | .last += 0.4),
          # Two sessions of one rebase step: one entry, their writes added up (750, the third; apart, neither is shown).
          s("c20261118T200000-beta-22"; "claude-sonnet-5-5"; "11:20:00"; "11:40:00"; 400; 0),
          s("c20261118T200000-beta-22"; "claude-sonnet-5-5"; "11:42:00"; "11:48:00"; 350; 0),
          # The second fix round, a step of its own (sixth, left out).
          s("c20261118T200000-beta-22"; "claude-sonnet-5-5"; "11:51:00"; "11:54:00"; 600; 0),
          # A build that began before the 24 h: only what it wrote in them, as dashboard_limit.py counts it.
          s("c20261118T200000-beta-22"; "claude-opus-5-5"; "2026-11-18T12:00:10Z"; "07:39:00"; 300; 0),
          # A card with no steps in the Metrics steps: named by its card id, with no step.
          s("c20261119T110000-gamma-33"; "claude-opus-5-5"; "11:00:00"; "11:10:00"; 650; 0)])}},
        # A Claude reviewer and judge keep no transcript: their writes are their review line'"'"'s (writes, judgeWrites),
        # never in cards. Bug caught: an alert that read transcripts alone, so it never named a review or a judge.
        metrics: {steps: ($steps // [
          {repo: "alpha", card: "c20261119T090000-alpha-11", issue: 11, steps: [{step: "build", time: "2026-11-19T10:00:00Z"},
            {step: "review", time: "2026-11-19T10:10:00Z", writes: {model: "claude-sonnet-5-5", write: 400, write1h: 0},
              judgeWrites: {model: "claude-haiku-5-5", write: 500, write1h: 200}}, {step: "test", time: "2026-11-19T10:20:00Z"}]},
          # A review line before the 24 h: what its judge wrote is not of them.
          {repo: "beta", card: "c20261118T200000-beta-22", issue: 22, steps: [{step: "review", time: "2026-11-18T11:00:00Z",
              judgeWrites: {model: "claude-haiku-5-5", write: 9999, write1h: 0}}, {step: "build", time: "2026-11-19T07:40:00Z"},
            {step: "fix", time: "2026-11-19T11:00:00Z"}, {step: "rebase", time: "2026-11-19T11:50:00Z"}, {step: "fix", time: "2026-11-19T11:55:00Z"}]}])}}]')" \
    -f "$SOURCE/.claude/scripts/dashboard_alerts.jq" | jq -r '.alerts[] | select(.id | startswith("cache-write-")) | .text'
}

got=$(alert 8)
# By tokens written: 4000, 3000, 750, 700, 650 shown; 600, 400 (the review) and 300 left out. The rest: 9000 - 5800
# 5-minute and 4000 - 3500 1-hour, the transcripts' writes of the 24 h made in no card's worktree (the review's and
# judge's are not among them, so they are not taken off).
want='8% of input tokens over the last 24 h were written to cache, over 5%. The card steps that wrote the most cache in those 24 h (5-minute + 1-hour cache write tokens): alpha#11 build claude-opus-5-5 3000+1000; beta#22 fix claude-sonnet-5-5 500+2500; beta#22 rebase claude-sonnet-5-5 750+0; alpha#11 judge claude-haiku-5-5 500+200; gamma#33 (no step recorded) claude-opus-5-5 650+0. Cache writes of those 24 h that no card step accounts for: 3200+500. Action: read the records of the card steps named here'
[ "$got" = "$want" ] || fail "the cache-write alert over the card steps:
got:  $got
want: $want"
case $got in *waste*) fail "the alert calls a write waste: $got" ;; esac
# No transcript of a card wrote cache: the review and judge are named from their line, and all the transcripts' writes
# are the one line.
got=$(alert 8 '[]')
want='8% of input tokens over the last 24 h were written to cache, over 5%. The card steps that wrote the most cache in those 24 h (5-minute + 1-hour cache write tokens): alpha#11 judge claude-haiku-5-5 500+200; alpha#11 review claude-sonnet-5-5 400+0. Cache writes of those 24 h that no card step accounts for: 9000+4000. Action: read the records of the card steps named here'
[ "$got" = "$want" ] || fail "the cache-write alert over a review and judge alone:
got:  $got
want: $want"
# No card wrote cache: all of it is the one line, and the action names what is left to find.
got=$(alert 8 '[]' '[]')
want='8% of input tokens over the last 24 h were written to cache, over 5%. No card step wrote cache in those 24 h. Cache writes of those 24 h that no card step accounts for: 9000+4000. Action: find the sessions outside the cards that wrote this cache'
[ "$got" = "$want" ] || fail "the cache-write alert with no card step:
got:  $got
want: $want"

# At 5% (the threshold) and under it: no alert at all.
[ -z "$(alert 5)" ] || fail "an alert at 5%, the threshold: $(alert 5)"
[ -z "$(alert 2.5)" ] || fail "an alert below the threshold: $(alert 2.5)"
echo "dashboard-alerts: ok"
