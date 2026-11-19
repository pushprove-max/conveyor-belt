# dashboard_alerts.jq -- the Alerts card's rules, pure:
# dashboard.sh passes only what it already collected, so the tests run these
# rules without a collect. Inputs: $parts (the snapshot's parts), $srcs (their
# source records), $preva ([{key: since epoch}] from the last collect), $now.
# Output {alerts, resolved, since, missing}; resolved is always empty (no kept rule recovers by a recorded event) and
# is kept for the readers of this shape. An id is <key>-<since epoch>: stable while
# the condition lasts, new once it clears and comes back (the Foreman's watcher
# wakes on any id it has not seen). missing names each input not measured now.
def r: . * 10 | round | . / 10;
def ts: try (sub("\\.[0-9]+"; "") | fromdateiso8601) catch null;
# Every alert asks for something (the owner's rule: no alert that needs no action): its text ends with the action.
def a($key; $sev; $text; $action): {key: $key, severity: $sev, text: "\($text). Action: \($action)"};
($parts | add // {}) as $d
| ($srcs | add // {}) as $src
| [
    # Used ahead of the week's elapsed share runs out before the reset at this pace.
    # A machine set to API billing paces dollars instead (limit-api below): the two percent alerts stay quiet there.
    ($d.limit // {} | select(.billing != "api" and .usedPct != null and .goalPct != null and .goalPct > 0 and .usedPct > .goalPct)
      | a("limit-claude"; "crit"; "Claude 7-day limit is on pace to run out before the reset: \(.usedPct | r)% used with \(.goalPct | r)% of the week gone";
          "slow Conveyor (a lower builder-cap) or move work to Codex")),
    ($d.limit // {} | select(.billing != "api") | .codex // {} | select(.usedPct != null and .goalPct != null and .goalPct > 0 and .usedPct > .goalPct)
      | a("limit-codex"; "crit"; "Codex 7-day limit is on pace to run out before the reset: \(.usedPct | r)% used with \(.goalPct | r)% of the week gone";
          "slow Conveyor (a lower builder-cap) or move work to Claude")),
    # A machine that pays by API: dollars spent ahead of the weekly limit's even pace. No limit, no alert.
    ($d.limit.api // {} | select(.limitUsd != null and .spentUsd != null and .goalUsd != null and .spentUsd > .goalUsd)
      | a("limit-api"; "crit"; "API spend is on pace to pass the weekly limit before Monday: $\(.spentUsd | round) spent, the even pace for now is $\(.goalUsd | round) of $\(.limitUsd | round)";
          "slow Conveyor (a lower builder-cap) or move work to the other provider")),
    # Kept by measurement: every day from 2026-10-11 to 10-18 wrote 1.7% to 3.3%. It names where the writes came from:
    # the limit's cacheWrites24h.cards (each card, session and model's writes in the 24 h, counted by request as the
    # share is: dashboard_limit.py cache_writes()), each put to its card's step by the Metrics steps ($d.metrics.steps,
    # every card's steps of the last 25 h): the first step line at or after the session's last request, in whole
    # seconds as a step line's time is; a session after its card's last step line has no step recorded. A Claude
    # reviewer or judge keeps no transcript, so the writes of each review and judge are its step line's (writes,
    # judgeWrites), for a step line of the 24 h; the share does not count them, so the rest line is the share's writes
    # less the transcripts' card writes. The card steps that wrote the most first, up to five, and the rest as one
    # line. It says what was written, never that a write was waste.
    ($d.limit.cacheWritePct24h // null | select(. != null and . > 5) as $pct
      | ($d.limit.cacheWrites24h | if type == "object" then . else {} end) as $w
      | ([$d.metrics.steps // [] | .[]? | objects | select(.card | type == "string") | {key: .card, value: .}] | from_entries) as $steps
      | def who($card): $steps[$card] as $c
          | $c.name // (if $c != null then "\($c.repo // "")#\($c.issue)" else ($card | capture("^c[0-9]{8}T[0-9]{6}-(?<r>.+)-(?<n>[0-9]+)$") | "\(.r)#\(.n)") // $card end);
        def entry($m; $w5; $w1): {model: ($m | strings // "no model recorded"), w5: ($w5 | numbers // 0), w1: ($w1 | numbers // 0)};
      [($w.cards // [] | .[]? | objects | select((.card | type) == "string" and (.first | type) == "number" and (.last | type) == "number") | . as $s
          | ([$steps[$s.card].steps // [] | .[]? | objects | . + {at: (.time | strings | ts)} | select(.at != null)] | sort_by(.at)
             | map(select(.at >= ($s.last | floor))) | .[0]) as $st
          | {id: [$s.card, $st.at], who: who($s.card), step: (if $st == null then "(no step recorded)" else $st.step end), ledger: false}
            + entry(.model; .write; .write1h)),
        ($steps[] | . as $c | .steps // [] | .[]? | objects | (.time | strings | ts) as $at | select($at != null and $at >= $now - 86400)
          | (["review", .writes], ["judge", .judgeWrites]) as [$step, $x] | $x | objects
          | {id: [$c.card, $at], who: who($c.card), step: $step, ledger: true} + entry(.model; .write; .write1h))]
      # One entry a card step (its card and step line; the judge apart) and model: its sessions' writes added up.
      | group_by([.id, .step, .model, .ledger]) | map(.[0] + {w5: (map(.w5) | add), w1: (map(.w1) | add)}) | map(select(.w5 + .w1 > 0))
      | sort_by(-(.w5 + .w1)) as $cw
      | [$cw[] | select(.ledger | not)] as $tw
      | ([{w5: ([(($w.write | numbers // 0) - ([$tw[].w5] | add // 0)), 0] | max), w1: ([(($w.write1h | numbers // 0) - ([$tw[].w1] | add // 0)), 0] | max)}
          | select(.w5 + .w1 > 0)] | .[0]) as $rest
      | a("cache-write"; "warn"; "\($pct | r)% of input tokens over the last 24 h were written to cache, over 5%"
          + (if $cw == [] and ($w.cards | type) != "array" then ""
             elif $cw == [] then ". No card step wrote cache in those 24 h"
             else ". The card steps that wrote the most cache in those 24 h (5-minute + 1-hour cache write tokens): "
               + ([$cw[:5][] | "\(.who) \(.step) \(.model) \(.w5)+\(.w1)"] | join("; ")) end)
          + (if $rest == null then "" else ". Cache writes of those 24 h that no card step accounts for: \($rest.w5)+\($rest.w1)" end);
          if $cw == [] then "find the sessions outside the cards that wrote this cache" else "read the records of the card steps named here" end)),
    ($d.guardBlocks // {} | select(.lastHour != null and .perHour != null and .lastHour >= 30 and .lastHour > 3 * .perHour)
      | a("guard-spike"; "warn"; "\(.lastHour) guard blocks in the last hour, over 3 times the \(.perHour | r) an hour average";
          "find the session looping on a refused command and redirect it")),
    ($d.host // {} | select(.cpus != null and .load != null and .load[0] > .cpus)
      | a("host-load"; "warn"; "Host overloaded: load \(.load[0]) on \(.cpus) cores";
          "hold new cards and stop any stray process")),
    ($d.host.swap // {} | select((.totalMb // 0) > 0 and .usedMb != null and .usedMb * 100 > .totalMb * 75)
      | a("host-swap"; "warn"; "Host swap \(.usedMb * 100 / .totalMb | round)% used (\(.usedMb) of \(.totalMb) MB)";
          "hold new cards and stop any stray process")),
    (("dev", "prod") as $e | $d.deploys[$e].runs[0]? // empty | select(.conclusion == "failure" or .conclusion == "timed_out")
      | a("deploy-\($e)"; if $e == "prod" then "crit" else "warn" end; "\($e) deploy failed: \(.title // "untitled") (\(.sha // "no sha"))";
          if $e == "prod" then "tell the owner (only the owner deploys PROD)" else "read the run and fix it" end)
        + {since: (.createdAt | ts)}),
    ($d.needsMax.decisions // [] | .[] | (.askedAt | ts) as $at | select($at != null and $now - $at > 3600)
      | a("question-\(.id)"; "warn"; "Question waiting on the owner over 1 h: \(.question)"; "the owner answers the question") + {since: $at}),
    # Collector stale: an input serving its last good read.
    ($src | to_entries[] | select(.value.status == "stale")
      | a("stale-\(.key)"; "warn"; "Collector input \(.key) is stale: \(.value.error // "its last read failed")"; "fix the collector input named here")
        + {since: (.value.staleSince | ts)})
  ]
| map(. + {since: (.since // $preva[0][.key] // $now)}) as $all
| [$all[] | select(.resolved != true)] as $act
| {alerts: [$act[] | {id: "\(.key)-\(.since)", severity, text, since: (.since | todate)}],
   resolved: [],
   since: (reduce $act[] as $x ({}; .[$x.key] = $x.since)),
   missing: [
     (if $d.limit.billing == "api" then empty elif $d.limit.usedPct == null or $d.limit.goalPct == null then "7-day limit" else empty end),
     (if $d.limit.billing == "api" then empty elif $d.limit.codex.subscription == false then empty elif $d.limit.codex.usedPct == null or $d.limit.codex.goalPct == null then "Codex 7-day limit" else empty end),
     (if $d.limit.billing != "api" then empty elif $d.limit.api.spentUsd == null then "API spend"
      elif $d.limit.api.complete != true then "API spend (incomplete)" else empty end),
     (if $d.limit.cacheWritePct24h == null then "24 h cache write share" else empty end),
     (if $d.guardBlocks.lastHour == null or $d.guardBlocks.perHour == null then "guard blocks per hour" else empty end),
     (if $d.host.load == null or $d.host.cpus == null then "host load" else empty end),
     (if $d.host.swap == null then "host swap" else empty end),
     (("dev", "prod") as $e | if $d.deploys[$e].runs == null then "\($e) deploy runs" else empty end),
     (if $d.needsMax.decisions == null then "questions for the owner" else empty end)
   ]}
