# METRICS in conveyor.sh: the definitions of a card's measurements and a window's totals (the comment above METRICS there).

    def med: sort | if length == 0 then null else (.[(length - 1) / 2 | floor] + .[length / 2 | floor]) / 2 end;
    def spread: sort | if length == 0 then {p50: null, p90: null} else {p50: (med | round), p90: (.[([((length * 0.9) | ceil) - 1, 0] | max)] | round)} end;
    def r3: if . == null then null else . * 1000 | round / 1000 end;
    def share(f): if length == 0 then null else (map(select(f)) | length) / length | r3 end;
    def pos($a; $x): $a | bsearch($x) | if . < 0 then -1 - . else . end;
    def blockclass($yes; $tail): if startswith($yes) then "visible change" elif test("prompt is too long"; "i") or ($tail | test("prompt is too long"; "i")) then "prompt too long"
      elif test("exit 124[^0-9]") then "timeout" elif test("changed tests") then "tests failed" elif test("conflict") then "conflict"
      elif test("no change|changed nothing") then "no change"
      elif test("^(build|fix|rebase|review [0-9]+|review of)[: ]|session failed|review failed|without one clear verdict") then "session failed" else "other" end;
    def cardm($now; $blocks; $st; $sf; $every; $yes): . as $c | .x.log as $log | ($log[0] // {}) as $p
      | def secs($k): [$log[] | select(.step == $k or .failed == $k) | .took | numbers] | if length == 0 then null else add end;
      ([.steps[] | select(.step == "review" and (.result | IN("fail", "stopped") | not))]) as $rv
      | ([$blocks[] | select(.issue == $c.issue and .end <= $c.startedAt)]) as $before
      | (try ($p.created | fromdate) catch null) as $cr | ($c.startedAt | fromdate) as $pk
      | ($c.x.limit // {before: null, after: null}) as $lim
      | {queueSec: (if $cr == null then null else $pk - $cr end),
         slotSec: (if $cr == null or $cr > $pk then null elif pos($st; $pk + 0.5) - pos($st; $cr - 0.5) == 0 then null
           else (pos($sf; $pk + 0.5) - pos($sf; $cr - 0.5)) * $every end),
         buildSec: secs("build"), reviewSec: secs("review"), fixSec: secs("fix"), testSec: secs("test"), rebuildSec: secs("rebase"),
         # A landing that met a conflict ran until the rebuild began (the start line of the rebuild): those seconds are
         # landing seconds too, added to those of the landing that landed.
         # A card whose issue was closed while it was blocked (x.blockedAt) landed nothing: the time to its closed line
         # is time waiting on the owner (waitMaxSec), not a landing's, a lead's or a cycle's.
         landSec: ([$log[] | select($c.x.blockedAt == null and (.step | IN("landed", "closed"))) | .took | numbers] | first
           | if . == null then null else . + ([$log[] | select(.step == "start" and .of == "rebase") | .took | numbers] | add // 0) end),
         pushSec: (([$log[] | select(.step == "pushed")] | first) as $pu | ([$log[] | select(.step == "landed")] | first) as $l
           | if $pu != null and $l != null then ($pu.time | fromdate) - ($l.time | fromdate) else null end),
         waitMaxSec: ([($before | max_by(.end) | select(. != null) | ([(.to // $c.startedAt), $c.startedAt] | min | fromdate) - (.end | fromdate)),
             (if $c.step == "blocked" and ($c.x.retried | not) then $now - ($c.x.endAt | fromdate) else empty end),
             (if $c.x.blockedAt != null then ($c.x.endAt | fromdate) - ($c.x.blockedAt | fromdate) else empty end)] | if length == 0 then null else add end),
         leadSec: (if ($c.step | IN("landed", "closed")) and $c.x.blockedAt == null and $cr != null then ($c.x.endAt | fromdate) - $cr else null end),
         cycleSec: (if ($c.step | IN("landed", "closed")) and $c.x.blockedAt == null then ($c.x.endAt | fromdate) - $pk else null end),
         # runSec: the card's pick-up to its end (to now while it is open); fixes and testRuns: its fix and test lines.
         runSec: ([(($c.x.endAt | if . == null then $now else fromdate end) - $pk), 0] | max),
         fixes: ([$log[] | select(.step == "fix")] | length), testRuns: ([$log[] | select(.step == "test")] | length),
         reviews: ($rv | length), firstReview: ($rv[0].result // null),
         findings: (if ($rv | length) == 0 or any($rv[]; .counts == null) then null
           else reduce $rv[].counts as $k ({P0: 0, P1: 0, P2: 0, P3: 0}; with_entries(.value += $k[.key])) end),
         rebuilds: ([$log[] | select(.step == "rebase")] | length), retries: ($before | length),
         blockClass: (if $c.step == "blocked" then ($c.reason | blockclass($yes; $c.tail // "")) else null end),
         depth: $c.x.depth, followups: ($c.x.followups | length), diff: $c.x.diff,
         # A reading lower at the end than at the start means the weekly limit reset during the card: what it took
         # before the reset is not known, so used is null, never a negative figure.
         limit: ($lim + {used: (if $lim.before != null and $lim.after != null and $lim.after >= $lim.before
           then ($lim.after - $lim.before) * 100 | round / 100 else null end)}),
         usd: $c.usd, tokens: (if any($c.steps[]; .unread != null) then null else [$c.steps[] | (.tokens.claude // 0) + (.tokens.codex // 0)] | add // 0 end),
         unpriced: ([$c.steps[] | select(.usd == null)] | length),
         timeline: [$c.steps[] | {step, result, time, sec: (.ran // .sec),
           tokens: (if .unread != null then null else (.tokens.claude // 0) + (.tokens.codex // 0) end), usd,
           model: (.pricedAs // .model), effort, counts, tests, stats, unpriced: (.unpriced // null)} + (if .override == true then {override: true} else {} end)
           # The cache writes of a review's reviewer (writes) and judge (judgeWrites), {model, write, write1h}, when they
           # wrote any: a Claude reviewer or judge keeps no transcript (--no-session-persistence), so the cache-write
           # alert reads them here.
           + (if .step == "review" and (.usage | type) == "object" and ((.usage.write | numbers // 0) + (.usage.write1h | numbers // 0)) > 0
              then {writes: {model, write: (.usage.write | numbers // 0), write1h: (.usage.write1h | numbers // 0)}} else {} end)
           + (if .judgeWrites then {judgeWrites} else {} end)
           # The route a Claude or Codex session took (session1(), claudereview(), codexreview()): subscription or proxy, when a proxy is set.
           + (if .route then {route} else {} end)]};
    # The totals of the cards that ended in a window, with the loop and host samples and the pushes of that window.
    # waitMaxSec of a window is every stretch waiting on the owner ($waits: {from, to} in epoch seconds, from a blocked card
    # ending to its issue next being picked, or to now) clipped to the window, $t0 to $t1: a card blocked yesterday
    # and still blocked counts today from midnight, and only the part of a long wait that fell in the window counts.
    def totals($cs; $smp; $pu; $every; $waits; $t0; $t1):
      # A card whose issue was closed while it was blocked (x.blockedAt) landed nothing: it is in cards, not in landed.
      # A landed card's dollars and tokens are those of every run of its issue (runSteps: the runs before a retry too).
      ($cs | map(select((.step | IN("landed", "closed")) and .x.blockedAt == null))) as $l | ($cs | map(select(.step == "blocked"))) as $b | [$l[] | (.runSteps // .steps)[]] as $ls
      | def tok: (.tokens.claude // 0) + (.tokens.codex // 0);
      {cards: ($cs | length), landed: ($l | length), blocked: ($b | length),
       leadSec: ([$l[].metrics.leadSec | numbers] | spread), cycleSec: ([$l[].metrics.cycleSec | numbers] | spread),
       firstReviewPass: ([$cs[].metrics.firstReview | strings] | share(. == "GO")),
       findingsPerCard: ([$cs[].metrics.findings | objects | add] | if length == 0 then null else add / length | r3 end),
       followupRate: ($l | share(.metrics.followups > 0)), blockRate: ($cs | share(.step == "blocked")),
       blocks: ($b | group_by(.metrics.blockClass) | map({key: .[0].metrics.blockClass, value: length}) | from_entries),
       rebuildRate: ($cs | share(.metrics.rebuilds > 0)),
       # The test failures by verdict (verdicts()): the card's (to its fix), main's (it waited) or flaky; and mainSec,
       # the seconds the runs of failing cases on main took, the time that check cost.
       testFailures: ([$cs[].x.log[] | select(.step == "test")] as $t | [$t[].verdicts[]?.verdict] as $v
         | {card: ($v | map(select(. == "card")) | length), main: ($v | map(select(. == "main")) | length),
            flaky: ($v | map(select(. == "flaky")) | length), mainSec: ([$t[].mainSec | numbers] | add // 0)}),
       # The dollars are those of the priced steps; leftOut counts the steps with no price (each says why in the
       # timeline of its card), so a figure with steps left out is never read as complete. The tokens are those of
       # the steps whose usage was read; tokensLeftOut counts the steps whose usage was not (unread: their tokens are
       # missing, not 0). By model, a priced step is split between the models that ran it (pricedBy); an unpriced
       # one counts under the model its line names.
       perLanded: (if ($l | length) == 0 then null else ($l | length) as $n | {
         usd: ([$ls[].usd | numbers] | add // 0 | . / $n * 10000 | round / 10000), leftOut: ([$ls[] | select(.usd == null)] | length),
         tokens: (([$ls[] | select(.unread == null) | tok] | add // 0) / $n | round), tokensLeftOut: ([$ls[] | select(.unread != null)] | length),
         byModel: ([$ls[] | select(.step != "test")
             | if (.pricedBy | type) == "object" then .pricedBy | to_entries[] | {m: .key, usd: .value.usd, tokens: .value.tokens}
               else {m: (.pricedAs // .model // "no model"), usd: null, tokens: (if .unread != null then null else tok end)} end]
           | group_by(.m) | map({key: .[0].m, value: {
           usd: ([.[].usd | numbers] | add // 0 | . / $n * 10000 | round / 10000), leftOut: (map(select(.usd == null)) | length),
           tokens: ([.[].tokens | numbers] | add // 0 | . / $n | round), tokensLeftOut: (map(select(.tokens == null)) | length)}}) | from_entries)} end),
       waitMaxSec: ([$waits[] | [([.from, $t0] | max), ([.to, $t1] | min)] | select(.[1] > .[0]) | .[1] - .[0]] | add // 0),
       limitPerCard: ([$cs[].metrics.limit.used | numbers] | med),
       loop: (if ($smp | length) == 0 then null else {samples: ($smp | length),
         utilisation: ([$smp[] | select((.cap | type) == "number" and .cap > 0) | .slots / .cap] | if length == 0 then null else add / length | r3 end),
         slotsMax: ([$smp[].slots] | max),
         idleSec: ([$smp[] | select(.slots == 0 and (.queued | type) == "number")] | if length == 0 then null else map(select(.queued > 0)) | length * $every end),
         idleUnreadSec: ([$smp[] | select(.slots == 0 and (.queued | type) != "number")] | length * $every),
         heldSec: ([$smp[] | select(.state != "running" and (.cap | type) == "number" and .slots < .cap)] | length * $every)} end),
       pushes: {ok: ([$pu[] | select(.step == "pushed") | .head // .time] | unique | length), failed: ([$pu[] | select(.step == "push")] | length),
         sec: ([$pu[] | select(.step == "pushed")] | group_by(.head // .time) | map(.[0].sec | numbers) | spread),
         failSec: ([$pu[] | select(.step == "push") | .sec | numbers] | spread)},
       host: (if ($smp | length) == 0 then null else {loadMax: ([$smp[].load | numbers] | max), memUsedMaxKb: ([$smp[].memUsedKb | numbers] | max),
         diskFreeMinKb: ([$smp[].diskFreeKb | numbers] | min)} end)};

