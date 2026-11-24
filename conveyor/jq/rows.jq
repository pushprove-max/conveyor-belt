# rows() in conveyor.sh: every card as one row. Arguments: $max (reviews a card), $nodeps, $yes and $lintyes (how those reasons begin),
# $shut (the reason of the closed line of a card whose issue was closed while it was blocked) and $ownshut (that of a card the owner shut).
# A card's row is made from its lines in record order (push lines left out), each folded into the card's state (fold),
# and the state then made a row (row). The state is what the row needs of the lines read so far, so a card's row after
# one more line needs its state and that line, not its older lines.
# states, when given (--slurpfile: the states snaprows() kept), holds the state of some cards, and the input holds the
# lines past the ones each state read. The answer is then [row, state] of each card the input names.
# Each line is a mark or not (fold's $mark: start, filed, pushed and issue lines are marks); the state counts some of
# its fields over all the card's lines and some over the lines that are no mark (start).
# A closing line ($end, endline): the last landed, closed or blocked line; a blocked line that a later landed, pushed or
# closed line of the card follows in the record does not count (a loop restart blocked a card that had landed, and its
# push still went out). Record order, not time: a push that started before the block is written after it. So it is
# the last of those lines (le) when that one is a blocked line, else the last landed or closed line (lc).
def endline: {step, result, sha, reason, retriedWhy, tail, kept, time, retriedAt, followups, rollout, diff, paths, batch, limit};
def row: . as $s | $s.first as $f | $s.r as $r | $s.l as $l
      | (if $s.le.step == "blocked" then $s.le else $s.lc end) as $end
      | (if $l.step == "brief" then (if $f.branch then "review" elif $s.wl then "landing"
          elif $s.wr then "review" else "build" end) elif $l.step | IN("build", "fix", "rebase") then "review"
         elif $l.step == "test" then (if $l.result == "fail" then "fix" else "landing" end)
         elif $l.step != "review" then "picked" elif $l.result == "GO" then "landing"
         elif $l.result != "NO-GO" then "review" elif $r < $max and ($s.rf | not) then "fix" else "landing" end) as $at
      # name: what a main-red fix card (issue 0, its picked line naming main's commit: mainred.sh redpick()) is shown as, in place
      # of an issue number, "Main is red (<commit>)"; a Tests page card of no issue (its picked line naming its test file:
      # testpick(), lib/testaction.sh), "Tests page: <file>"; a card of another kind with no issue (noIssue), that name; null for any other card, which is shown by its issue.
      | {card: $f.card, issue: $f.issue, name: (($f.mainRed | strings | "Main is red (\(.[0:12]))") // ($f.testFile | strings | "Tests page: \(.)") // $f.noIssue // null), title: ($f.title // ""), step: ($end.step // $at),
         stage: ({picked: 0, build: 1, fix: 3, landing: 5}[$at] // (if $r + (if $l.step == "review" then 0 else 1 end) > 1 then 4 else 2 end)),
         reviews: $r, startedAt: $f.time, stepAt: $s.gt,
         # seats: the judge's call of the rule Pick settings before the card (pickjudge(), lib/modelpick.sh), priced as a step of its own.
         # The sessions and reviews (stepline), then the ones a blocked line says failed (spentline).
         steps: ($s.s1 + $s.s2),
         # A card the loop retried itself (retriedWhy, retry()) says why after its reason; x.retriedWhy holds that note
         # alone, so the snapshot's earlier attempt can keep it out of the reason it parses (lib/snapshot.sh reasonOf).
         result: ($end.result // ""), sha: ($end.sha // ""), reason: (($end.reason // "") + ($end.retriedWhy // "" | if . == "" then "" else "; " + . end)), tail: ($end.tail // ""), kept: ($end.kept // ""),
         x: {at: (if $at == "picked" then "brief" elif $at == "landing" and $l.step != "test" then "tests" else $at end),
             review: (if $at == "review" then $r + 1 else null end),
             tokens: {claude: $s.tc, codex: $s.tx},
             endAt: ($end.time // null), retriedAt: ($end.retriedAt // null), retriedWhy: ($end.retriedWhy // null),
             # When a card whose issue was closed while it was blocked, or that the owner shut (shut()), was blocked,
             # else null: from then to its end it waited on the owner, and none of that time is a landing's.
             blockedAt: (if $end.step == "closed" and ($end.reason | IN($shut, $ownshut)) then $s.lb else null end), followups: ($end.followups // []), rollout: ($end.rollout // []), branch: ($f.branch // null), base: ($f.base // null),
             diff: ($end.diff // null), paths: ($end.paths // null), batch: ($end.batch // null), depth: $s.dep,
             # The blocked card whose kept patch this card resumes (named by its first worktree line), else null.
             from: ($s.wt | .reason // "" | select(test("built from nothing") | not)
               | capture("kept patch of card (?<c>c[A-Za-z0-9-]+)").c) // null,
             # The accounts it started on, as its worktree line names them (null: the default login; for a review, its
             # account); null before that line.
             accounts: ($s.wt | if . == null then null else {account: (.account // null), reviewAccount: (.reviewAccount // null)} end),
             limit: {before: ($s.wt | .limit // null), after: ($end.limit // null)},
             visible: ($s.vis // ""),
             # The last Done-when check of a session's reply ({items, met, failed}), else null.
             doneWhen: $s.dw,
             # How many times a build, fix, rebase or review of the card made no progress and was ended (watch()).
             stalls: $s.st,
             # Why its picked line took a slot beyond the project's cap (pick(): "main is red"), else null.
             beyond: ($f.beyond // null),
             # Its split line (splitcheck(), lib/slices.sh): {result: kept or split, slices: how many the judge gave,
             # filed: the slices filed (the rule On), else null}; null for a card the rule did not check.
             split: ($s.sp | if . == null then null else {result, slices: (.split.slices // [] | length), filed: (.split.filed // null)} end),
             # Its pick (modelpick(), lib/modelpick.sh): the one its last line with a pick holds; null for a card the
             # rule Pick settings did not pick.
             pick: $s.pk,
             log: $s.log}};
# The log entry of a line: $i its place in the card's lines, $pt the time of the line before it.
def logline($i; $pt): {step, of, result, time, counts, created, sec: (if .step == "pushed" then .sec else null end), pr: (if .step == "pushed" then .pr else null end), flaky: (if .step == "pushed" then .flaky else null end), failed: (if .step == "blocked" then .spent.step else null end), n: (if .step == "filed" then .followups | length else null end),
               # An issue line, a test line and a review that failed, a blocked line (its sentence), a fix line (what started it), a worktree line (how it took up a kept patch) and a lint line (its commands' results) keep their reason; a blocked line and a failed test line their output and a NO-GO review its findings (tail); a failed test line its failing files (failures).
               reason: (if (.step == "issue" and .result != "ok") or (.step == "test" and .result != "pass") or (.step == "review" and (.result | IN("fail", "stopped")))
                 or .step == "blocked" or .step == "fix" or .step == "worktree" or .step == "lint" then .reason else null end),
               # A lint line's gate (lintline(), lib/lint.sh): the track names the lint fix that starts next by it.
               gate: (if .step == "lint" then .lint.gate else null end),
               # A lint line's commands (lintline()): the Board shows a row for each.
               lintCommands: (if .step == "lint" then .lint.commands else null end),
               # A GO review has its tail too when it holds a finding the judge found outside the card's change (an OUTSIDE line, card.sh).
               tail: (if .step == "blocked" or (.step == "test" and .result != "pass") or (.step == "review" and .result == "NO-GO") then .tail
                 elif .step == "review" and (.tail // "" | test("(^|\n)(OUTSIDE|SELFHEALS): ")) then .tail else null end),
               # A filed line's outside findings, each {finding, issue}: the Board names the follow-up of each under its review.
               outside: (if .step == "filed" then .outside else null end),
               failures: (if .step == "test" and .result != "pass" then .failures else null end),
               # A test line's failures' verdicts (card, main or flaky) and the seconds its run of them on main took (mainred.sh verdicts());
               # mainSec also on a start line of the test step after a wait for main, the seconds of the runs on main that wait took (card.sh mainwaited()).
               verdicts: (if .step == "test" then .verdicts else null end), mainSec: (if .step == "test" or .step == "start" then .mainRun.sec else null end),
               # The card whose landing turned main red, on a test line that found it (verdicts()); a blocked line's class (block()).
               brokeMain: (if .step == "test" then .brokeMain else null end), class: (if .step == "blocked" then .class else null end),
               # A test line whose failed cases ran again at once (tests()): two runs (track.jq runs); on a pass line,
               # it passed only when what had not passed ran again.
               rerun: (if .step == "test" and .rerun != null then true else null end),
               # A test line whose list left linked test files out (testcap(), testrun.sh), or ran only the changed cases of
               # the card's own test files (owncases(), testlist.sh): its note, which the track shows, and how many were left out.
               list: (if .step == "test" and ((.list.left? // 0) > 0 or .list.cases? != null) then {left: .list.left, why: .list.why} else null end),
               # A test line that reused the pass before it (card()): it keeps that pass's rerun on the track.
               reused: (if .step == "test" and .reused == true then true else null end),
               # A build, fix or rebase line whose Done-when check failed items: the fix that starts next is the reply
               # check's (donewhen.sh checked()), which the track draws on the step of the session it checks.
               checkFailed: (if (.step | IN("build", "fix", "rebase")) and ((.doneWhen.failed? // []) | length > 0) then true else null end),
               stop: (if .step != "blocked" then null else .reason | if startswith($nodeps) then "deps" elif startswith("worktree:") then "worktree" elif startswith("brief:") then "brief" elif startswith($yes) or startswith($lintyes) then "yes" else null end end),
               # A review's judge: {ran: true, accepted, declined, outside (how many findings it accepted, declined and found
               # outside the card's change, filed as follow-ups; outside only when it found any), selfheals (how many it wrote to
               # the self-heals list or the docs list, only when any), kinds (each accepted or outside finding the judge gave a kind, {finding,
               # effect, reason, outside: true for an outside one}, only when any: the Board shows the kind on its row), go
               # (the review's GO came from the judge accepting no finding)}; {ran: false, why} for a review it did not
               # read: its call failed or its answer was not read (why says), the review ended with no verdict or held
               # no finding, or the judge is off.
               judge: (if .step != "review" then null
                 elif (.judge.accepted | type) == "array" then {ran: true, accepted: (.judge.accepted | length), declined: (.judge.declined | length), go: (.result == "GO" and (.judge.accepted | length) == 0)}
                   + (.judge.outside // [] | length | if . > 0 then {outside: .} else {} end)
                   + (.judge.selfheals // [] | length | if . > 0 then {selfheals: .} else {} end)
                   + ([(.judge.accepted[] | objects | {finding, effect, reason}), (.judge.outside // [] | .[]? | objects | {finding, effect, reason, outside: true})]
                     | map(select(.effect | IN("harm", "self-heals", "cleanup", "already guarded", "docs drift"))) | if . == [] then {} else {kinds: .} end)
                 elif .judge.failed then {ran: false, why: .judge.failed}
                 elif .result | IN("GO", "NO-GO") | not then {ran: false, why: "the review did not end with a verdict"}
                 elif .reason // "" | split("\n") | any(test("^(NEW CARD|UNPROVEN|DECLINED):|^[[:space:]]*$") | not) then {ran: false, why: "the judge is off"}
                 else {ran: false, why: "the review had no finding"} end),
               # A NO-GO review's findings that came back after a fix round told to fix them (card.sh), {id, rounds}.
               survived: (if .step == "review" then .survived else null end),
               # The review line that ended the fix loop, and the filed line: why it ended (stop), with this card's own reviews
               # (the record's pass, given as own) and rounds then (card.sh loopstop()).
               loopEnd: (if (.step == "review" or .step == "filed") and (.stop | type) == "string" then {stop, own: .pass, rounds} else null end),
               # A grown line (growcheck(), lib/slices.sh): the files of the change before, and after the split (On).
               grown: (if .step == "grown" then {files: .grown.files, after: (.grown.after // null)} else null end),
               took: (if $i == 0 then null else (.time | fromdate) - ($pt | fromdate) end)} | with_entries(select(.value != null));
# A step of a line that is no mark and not the card's first such line: $pt is the time of the one before it.
def stepline($pt): {step, time, sec: ((.time | fromdate) - ($pt | fromdate)), tokens, usage} + (if .model then {model} else {} end)
      # judgeWrites: the cache writes of a review's judge session (the review line's judge), {model, write, write1h},
      # when it wrote any. A Claude judge keeps no transcript (--no-session-persistence), so its line is their one record.
      + ({result, effort, counts, tests, stats, unread, ran: .sec, route,
          judgeWrites: (.judge | if type == "object" and (.usage | type) == "object" and ((.usage.write | numbers // 0) + (.usage.write1h | numbers // 0)) > 0
            then {model, write: (.usage.write | numbers // 0), write1h: (.usage.write1h | numbers // 0)} else null end)} | with_entries(select(.value != null)));
# The session or review a blocked line says failed (spent): a step like the others, result fail.
def spentline($pt): .spent as $sp
      | {step: $sp.step, time, sec: ((.time | fromdate) - ($pt | fromdate)), tokens: {claude: ($sp.tokens.claude // 0), codex: ($sp.tokens.codex // 0)},
         usage: $sp.usage} + (if $sp.model then {model: $sp.model} else {} end)
      + ({result: "fail", effort: $sp.effort, stats: $sp.stats, unread: $sp.unread, ran: $sp.sec, route: $sp.route} | with_entries(select(.value != null)));
# The state of card $k before its first line. k: the card; an, at: how many lines it has, the last one's time; log: the
# log; le, lc, lb: the last closing line or push (endline), the last landed or closed line, the last blocked line's
# time. Of the lines that are no mark: n, gt: how many, the last one's time; first: the first one; l: the last one that
# is no closing line ({step, result}); r: the reviews; s1, s2: the steps (stepline, spentline); wl, wr: a worktree line
# took up a kept patch to land or to review it; rf: a rebase line or a failed test line; tc, tx: the tokens; dep: the
# last brief line's depth; wt: the first worktree line; vis: the last review line's visible; dw: the last Done-when
# check; st: the stalls; sp: the last split line; pk: the last pick.
def start($k): {k: $k, an: 0, at: null, log: [], le: null, lc: null, lb: null, n: 0, gt: null, first: null, l: null, r: 0, s1: [], s2: [],
      wl: false, wr: false, rf: false, tc: null, tx: null, dep: null, wt: null, vis: null, dw: null, st: null, sp: null, pk: null};
# The state after one more line of the card, $x.
def fold($x): .an as $i | .at as $pt | .gt as $gt | ($x.step | IN("start", "filed", "pushed", "issue")) as $mark
      | .log += [$x | logline($i; $pt)] | .an += 1 | .at = $x.time
      | if $x.step | IN("landed", "closed", "blocked", "pushed") then .le = ($x | endline) else . end
      | if $x.step | IN("landed", "closed") then .lc = ($x | endline) else . end
      | if $x.step == "blocked" then .lb = $x.time else . end
      | if $mark then . else
          (if .n == 0 then .first = ($x | {card, issue, mainRed, testFile, noIssue, title, time, branch, base, beyond})
           elif $x.step | IN("seats", "build", "review", "test", "fix", "rebase") then .s1 += [$x | stepline($gt)]
           elif $x.step == "blocked" and ($x.spent | type) == "object" then .s2 += [$x | spentline($gt)] else . end)
          | .n += 1 | .gt = $x.time
          | if $x.step | IN("landed", "closed", "blocked") then . else .l = ($x | {step, result}) end
          | .tc += $x.tokens.claude | .tx += $x.tokens.codex | .st += ($x.stalls // 0)
          | .rf = (.rf or $x.step == "rebase" or ($x.step == "test" and $x.result == "fail"))
          | if $x.step == "review" then .r += 1 | .vis = $x.visible
            elif $x.step == "brief" then .dep = ($x.depth // null)
            elif $x.step == "split" then .sp = ($x | {result, split})
            elif $x.step == "worktree" then .wt //= ($x | {reason, account, reviewAccount, limit})
              | .wl = (.wl or (($x.reason | strings | startswith("landing from the kept patch")) // false))
              | .wr = (.wr or (($x.reason | strings | startswith("reviewing the kept patch")) // false))
            else . end
          | if $x.doneWhen then .dw = $x.doneWhen else . end
          | if ($x.pick | type) == "object" then .pk = $x.pick else . end end;
($ARGS.named.states // null) as $kept
| map(select(.step != "push")) | group_by(.card)
| if $kept == null then map(reduce .[] as $x (start(.[0].card); fold($x)) | row)
  else ($kept | map({key: (.k | tojson), value: .}) | from_entries) as $ks
    | map(.[0].card as $k | reduce .[] as $x ($ks[$k | tojson] // start($k); fold($x)) | [row, .]) end
