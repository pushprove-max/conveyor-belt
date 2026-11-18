# rows() in conveyor.sh: every card as one row. Arguments: $max (reviews a card), $nodeps, $yes (how those reasons begin),
# $shut (the reason of the closed line of a card whose issue was closed while it was blocked).
map(select(.step != "push")) | group_by(.card) | map(. as $all
      | map(select(.step | IN("start", "filed", "pushed", "issue") | not)) | . as $g
      | (map(select(.step == "review")) | length) as $r
      # Its closing line: the last landed, closed or blocked line; a blocked line that a later landed, pushed or closed
      # line of the card follows in the record does not count (a loop restart blocked a card that had landed, and its push
      # still went out). Record order, not time: a push that started before the block is written after it.
      | ($all | map(select(.step | IN("landed", "closed", "blocked", "pushed"))) | . as $e
          | [range(length) as $i | $e[$i] | select(.step != "pushed" and (.step != "blocked" or ($e[$i + 1:] | all(.step == "blocked"))))] | last) as $end
      | (map(select(.step | IN("landed", "closed", "blocked") | not)) | last) as $l
      | (if $l.step == "brief" then (if $g[0].branch then "review" elif any(.step == "worktree" and (.reason | startswith("landing from the kept patch"))) then "landing"
          elif any(.step == "worktree" and (.reason | startswith("reviewing the kept patch"))) then "review" else "build" end) elif $l.step | IN("build", "fix", "rebase") then "review"
         elif $l.step == "test" then (if $l.result == "fail" then "fix" else "landing" end)
         elif $l.step != "review" then "picked" elif $l.result == "GO" then "landing"
         elif $l.result != "NO-GO" then "review" elif $r < $max and (any(.step == "rebase" or (.step == "test" and .result == "fail")) | not) then "fix" else "landing" end) as $at
      # name: what a main-red fix card (issue 0, its picked line naming main's commit: redpick()) is shown as, in place
      # of an issue number, "Main is red (<commit>)"; null for any other card, which is shown by its issue.
      | {card: .[0].card, issue: .[0].issue, name: (.[0].mainRed | strings | "Main is red (\(.[0:12]))") // null, title: (.[0].title // ""), step: ($end.step // $at),
         stage: ({picked: 0, build: 1, fix: 3, landing: 5}[$at] // (if $r + (if $l.step == "review" then 0 else 1 end) > 1 then 4 else 2 end)),
         reviews: $r, startedAt: .[0].time, stepAt: last.time,
         steps: [range(1; length) as $i | .[$i] | select(.step | IN("build", "review", "test", "fix", "rebase"))
           | {step, time, sec: ((.time | fromdate) - ($g[$i - 1].time | fromdate)), tokens, usage} + (if .model then {model} else {} end)
             + ({result, effort, counts, tests, stats, unread, ran: .sec, route} | with_entries(select(.value != null)))]
           # The session or review a blocked line says failed (spent): a step like the others, result fail.
           + [range(1; length) as $i | .[$i] | select(.step == "blocked" and (.spent | type) == "object") | .spent as $sp
             | {step: $sp.step, time, sec: ((.time | fromdate) - ($g[$i - 1].time | fromdate)), tokens: {claude: ($sp.tokens.claude // 0), codex: ($sp.tokens.codex // 0)},
                usage: $sp.usage} + (if $sp.model then {model: $sp.model} else {} end)
             + ({result: "fail", effort: $sp.effort, stats: $sp.stats, unread: $sp.unread, ran: $sp.sec, route: $sp.route} | with_entries(select(.value != null)))],
         # A card the loop retried itself (retriedWhy, retry()) says why after its reason: the Board's earlier attempt shows it.
         result: ($end.result // ""), sha: ($end.sha // ""), reason: (($end.reason // "") + ($end.retriedWhy // "" | if . == "" then "" else "; " + . end)), tail: ($end.tail // ""), kept: ($end.kept // ""),
         x: {at: (if $at == "picked" then "brief" elif $at == "landing" and $l.step != "test" then "tests" else $at end),
             review: (if $at == "review" then $r + 1 else null end),
             tokens: {claude: (map(.tokens.claude) | add), codex: (map(.tokens.codex) | add)},
             endAt: ($end.time // null), retriedAt: ($end.retriedAt // null),
             # When a card whose issue was closed while it was blocked (shut()) was blocked, else null: from then to
             # its end it waited on the owner, and none of that time is a landing's.
             blockedAt: (if $end.step == "closed" and $end.reason == $shut then $all | map(select(.step == "blocked")) | last | .time else null end), followups: ($end.followups // []), branch: (.[0].branch // null),
             diff: ($end.diff // null), paths: ($end.paths // null), batch: ($end.batch // null), depth: (map(select(.step == "brief")) | last | .depth // null),
             # The blocked card whose kept patch this card resumes (named by its worktree line), else null.
             from: (map(select(.step == "worktree")) | first | .reason // "" | select(test("built from nothing") | not)
               | capture("kept patch of card (?<c>c[A-Za-z0-9-]+)").c) // null,
             # The accounts it started on, as its worktree line names them (null: the default login; for a review, its
             # account); null before that line.
             accounts: (map(select(.step == "worktree")) | first | if . == null then null else {account: (.account // null), reviewAccount: (.reviewAccount // null)} end),
             limit: {before: (map(select(.step == "worktree")) | first | .limit // null), after: ($end.limit // null)},
             visible: (map(select(.step == "review")) | last | .visible // ""),
             # The last Done-when check of a session's reply ({items, met, failed}), else null.
             doneWhen: (map(select(.doneWhen)) | last | .doneWhen // null),
             # How many times a build, fix, rebase or review of the card made no progress and was ended (watch()).
             stalls: (map(.stalls // 0) | add),
             # Why its picked line took a slot beyond the project's cap (pick(): "main is red"), else null.
             beyond: (.[0].beyond // null),
             log: [range(0; $all | length) as $i | $all[$i] | {step, of, result, time, counts, created, sec: (if .step == "pushed" then .sec else null end), pr: (if .step == "pushed" then .pr else null end), failed: (if .step == "blocked" then .spent.step else null end), n: (if .step == "filed" then .followups | length else null end),
               # An issue line, a test line and a review that failed, a blocked line (its sentence) and a fix line (what started it) keep their reason; a blocked line and a failed test line their output and a NO-GO review its findings (tail); a failed test line its failing files (failures).
               reason: (if (.step == "issue" and .result != "ok") or (.step == "test" and .result != "pass") or (.step == "review" and (.result | IN("fail", "stopped")))
                 or .step == "blocked" or .step == "fix" then .reason else null end),
               tail: (if .step == "blocked" or (.step == "test" and .result != "pass") or (.step == "review" and .result == "NO-GO") then .tail else null end),
               failures: (if .step == "test" and .result != "pass" then .failures else null end),
               # A test line's failures' verdicts (card, main or flaky) and the seconds its run of them on main took (verdicts()).
               verdicts: (if .step == "test" then .verdicts else null end), mainSec: (if .step == "test" then .mainRun.sec else null end),
               # A test line that passed only when what had not passed ran again (tests()).
               rerun: (if .step == "test" and .result == "pass" and .rerun != null then true else null end),
               # A test line whose list left linked test files out (testcap(), testrun.sh), or ran only the changed cases of
               # the card's own test files (owncases(), testrun.sh): its note, which the track shows, and how many were left out.
               list: (if .step == "test" and ((.list.left? // 0) > 0 or .list.cases? != null) then {left: .list.left, why: .list.why} else null end),
               # A test line that reused the pass before it (card()): it keeps that pass's rerun on the track.
               reused: (if .step == "test" and .reused == true then true else null end),
               # A build, fix or rebase line whose Done-when check failed items: the fix that starts next is the reply
               # check's (testrun.sh checked()), which the track draws on the step of the session it checks.
               checkFailed: (if (.step | IN("build", "fix", "rebase")) and ((.doneWhen.failed? // []) | length > 0) then true else null end),
               stop: (if .step != "blocked" then null else .reason | if startswith($nodeps) then "deps" elif startswith("worktree:") then "worktree" elif startswith("brief:") then "brief" elif startswith($yes) then "yes" else null end end),
               # A review's judge: {ran: true, accepted, declined (how many findings it accepted and declined), go (the
               # review's GO came from the judge declining every finding)}; {ran: false, why} for a review it did not
               # read: its call failed or its answer was not read (why says), the review ended with no verdict or held
               # no finding, or the judge is off.
               judge: (if .step != "review" then null
                 elif (.judge.accepted | type) == "array" then {ran: true, accepted: (.judge.accepted | length), declined: (.judge.declined | length), go: (.result == "GO" and (.judge.accepted | length) == 0)}
                 elif .judge.failed then {ran: false, why: .judge.failed}
                 elif .result | IN("GO", "NO-GO") | not then {ran: false, why: "the review did not end with a verdict"}
                 elif .reason // "" | split("\n") | any(test("^(NEW CARD|UNPROVEN|DECLINED):|^[[:space:]]*$") | not) then {ran: false, why: "the judge is off"}
                 else {ran: false, why: "the review had no finding"} end),
               # A NO-GO review's findings that came back after a fix round told to fix them (card.sh), {id, rounds}.
               survived: (if .step == "review" then .survived else null end),
               took: (if $i == 0 then null else (.time | fromdate) - ($all[$i - 1].time | fromdate) end)} | with_entries(select(.value != null))]}})
