# TRACK in conveyor.sh: the definitions the snapshot draws a card's track with (the comment above TRACK there).

    def reviews: .x.log as $log | [$log | to_entries[] | select(.value.step == "review")] as $rv
      | [range(0; $rv | length) as $i | $rv[$i] as $e | {round: ($i + 1), verdict: $e.value.result, counts: ($e.value.counts // null), sec: ($e.value.took // null), judge: ($e.value.judge // null),
          survived: ($e.value.survived // []), loopEnd: ($e.value.loopEnd // null),
          fixed: ($log[$e.key + 1:($rv[$i + 1].key // ($log | length))] | any(.step == "fix" or (.step == "start" and .of == "fix")))}];
    # Where a step of this kind is drawn, from the state the card is in: after failed tests (tfix) the fix, its review
    # and the tests again are the tests step; from a rebuild on, everything is the landing step.
    def place($kind): if $kind == "file" then 16 elif $kind == "rebase" then 12 elif $kind == "land" or .phase == "rebuild" then 13 elif $kind == "build" or $kind == "proof" then 5
      elif .phase == "tfix" or $kind == "test" then 11 elif $kind == "review" then [6, 8, 10][[.nrev, 2] | min] else [7, 9][[.nfix, 1] | min] end;
    def track($of; $perr): . as $c | .x.log as $log
      | ["queued", "picked", "worktree ready", "dependencies linked", "brief written", "building", "review 1", "fix 1", "review 2", "fix 2", "review 3",
         "tests", "rebuild", "landing", "pushed", "issue closed", "follow-ups filed"] as $names
      | (reduce $log[] as $l ({s: [range(17) | {state: "todo", sec: null}], phase: "main", nrev: 0, nfix: 0, cur: null};
          def put($i; $st): .s[$i].sec = (.s[$i].sec // 0) + ($l.took // 0) | .s[$i].state = ($st // .s[$i].state) | .cur = $i;
          def main($st): if .phase == "main" then $st else null end;
          if $l.step == "picked" then .s[1].state = "done" | .s[0] = {state: "done", sec: (try (($l.time | fromdate) - ($l.created | fromdate)) catch null)}
          elif $l.step == "worktree" then put(2; "done") elif $l.step == "deps" then put(3; "done") elif $l.step == "brief" then put(4; "done")
          elif $l.step == "build" then put(5; "done")
          elif $l.step == "review" then put(place("review"); main("done")) | .nrev += 1
          elif $l.step == "fix" then put(place("fix"); main("done")) | if .phase == "main" then .nfix += 1 else . end
          # A held test line (card(): the machine's failures, issue 221) is no failure: the step is neither failed nor done.
          elif $l.step == "test" then place("test") as $i | put($i; if $l.result == "fail" then "failed" elif $l.result == "pass" and $i == 11 then "done" else null end)
            | if $l.result == "fail" and .phase == "main" then .phase = "tfix" else . end
          # The landing that met the conflict ran until the rebuild began: those seconds stay with the landing. The
          # seconds of the rebuild session, from its start line to its rebase line, are those of the rebuild step.
          elif $l.step == "start" and $l.of == "rebase" then put(13; null) | .phase = "rebuild" | .cur = 12
          # The split check's start line (splitcheck(), lib/slices.sh) comes before the worktree: no step of the track.
          elif $l.step == "start" and $l.of == "split" then .
          elif $l.step == "start" then .cur = place($l.of)
          elif $l.step == "rebase" then .phase = "rebuild" | put(12; "done")
          elif $l.step == "filed" then .s[16] = {state: "done", sec: ($l.took // null), n: ($l.n // 0)}
          elif $l.step == "landed" then put(13; "done") | (if .s[16].state == "todo" then .s[16].state = "skipped" else . end)
            | (if .s[12].state == "todo" then .s[12].state = "skipped" else . end)
            | if $c.issue == 0 then .s[15].state = "skipped" else . end
          elif $l.step == "closed" then .s[14].state = "skipped" | .s[15].state = "done" | .s[16].state = "skipped"
          elif $l.step == "pushed" then put(14; "done")
          elif $l.step == "issue" then .s[15] = {state: (if $l.result == "ok" then "done" else "failed" end), sec: ($l.took // null)}
          # A card that is blocked stopped in a step: the one that had begun (its start line), else the one its last
          # line ended, else the one its reason names (the worktree, the dependencies and the brief have no start
          # line). That step is failed, and the seconds it ran before the card was blocked are its seconds. A card
          # that waits for the yes of the owner failed nothing.
          elif $l.step == "blocked" then ({worktree: 2, deps: 3, brief: 4}[$l.stop // ""] // .cur) as $i
            | if $l.stop == "yes" or $i == null then . else .s[$i].sec = (.s[$i].sec // 0) + ($l.took // 0) | .s[$i].state = "failed" end
            # A card recorded when the worktree line came after the linking has none when the linking failed: the worktree was made.
            | if $l.stop == "deps" and .s[2].state == "todo" then .s[2].state = "done" else . end
          else . end)) as $t
      | ($log | last) as $last
      # A bug card's proof run (snapshot.sh: .proof) is drawn on Build, the step whose change it checks, never as the review after it.
      | (if $c.result != "" then null elif $last.step == "start" and $last.of != "split" then $last.of elif $c.proof then "proof"
         else {build: "build", review: "review", fix: "fix", tests: "test", landing: "land"}[$c.x.at] // null end) as $kind
      | ($c.x.after // null) as $after
      # wait: landed, not pushed, with push off: no step runs until the owner presses Push landed.
      | (if $after == "wait" then null elif $after then (if $after | IN("issue", "issuefail") then 15 else 14 end) elif $c.result != "" then null elif $kind then ($t | place($kind))
         elif $last.step == "picked" or ($last.step == "start" and $last.of == "split") then 2 elif $last.step == "worktree" then 3 else 4 end) as $at
      | ($t.nrev + 1) as $r
      # The fix in progress is the next one of the card, counted like the reviews: over every fix, a fix after failed tests too.
      | ([$log[] | select(.step == "fix")] | length + 1) as $f
      | (if $after == "wait" then "Landed, waiting for Push landed" elif $at == null then "" elif $after then {push: "pushing", pushfail: "push failed; it is tried again", pushheld: "push failed its check; tried again once main moves",issue: "waiting for GitHub to close the issue", issuefail: "GitHub did not close the issue"}[$after]
         elif $kind == null then ["making the worktree", "linking dependencies", "writing the brief"][$at - 2]
         elif $kind == "file" then "filing follow-ups" elif $kind == "rebase" then "rebuilding after a conflict" elif $kind == "land" then "landing" elif $kind == "build" then "building" elif $kind == "proof" then "proof run"
         elif $kind == "fix" and $t.phase != "main" then "fix after failed tests"
         elif $t.phase == "rebuild" then (if $kind == "review" then "review \($r) after the rebuild" else "tests after the rebuild" end)
         elif $t.phase == "tfix" then (if $kind == "review" then "review \($r) after the test fix" else "tests again" end)
         elif $kind == "review" then "review \($r)" + (if $r <= $of then " of \($of)" else "" end)
         elif $kind == "fix" then "fix after review \($t.nrev)" else "tests" end) as $label
      # The filing is the last step drawn and comes before the landing: it does not make the steps before it skipped.
      # Nor is the rebuild skipped by a landing that has only begun: that landing may yet meet a conflict.
      | ([(if $kind == "file" then null else $at end) // -1, ($t.s | to_entries | map(select(.value.state != "todo" and .key != 16) | .key) | max // -1)] | max | [., 14] | min) as $reached
      | [range(17) as $i | $t.s[$i] | {name: $names[$i], state: (if $i == $at then (if $label == "fix after failed tests" or ($after | IN("pushfail", "pushheld", "issuefail")) then "failed" else "now" end)
          elif .state == "todo" and $i < $reached and ($i != 12 or $reached > 13) then "skipped" else .state end), sec} + (if $i == 16 and .n != null then {n} else {} end)] as $detail
      # The six steps every card is drawn with: Build (the set-up from the worktree on, then the build; never
      # the time the issue sat queued), Review and Fix (every round, with their count), Test, Land (the rebuild after a
      # conflict is part of the landing) and Push (the push of main, the close of the issue and the follow-ups named on it).
      # The loop files the follow-ups before it lands: that filing is part of Land, so the track only ever moves on from
      # left to right (a filing drawn as Push would step back to Land when the landing begins).
      # Each is done, now, skipped, failed or todo, with its seconds.
      # A fix the Done-when check on a session's reply started (donewhen.sh checked(): its start right after a build,
      # fix or rebuild line whose Done-when check failed items (rows.jq checkFailed), its line's reason "the Done-when check failed") is part of the
      # step of the session it checks (last), never a Fix round of its own: after the build it is Build's, with a note
      # (replyFix: now while it runs, done after), so Fix is never ticked before the first review. rc: the start in
      # progress is one.
      # A lint fix (lintgate(), lib/lint.sh: its start right after a lint line with findings) is named by the gate on
      # that line (its lint.gate, rows.jq gate): the review gate's is the step of the session before it, as the reply check's is (after
      # the build, Build's, lintFix: now while it runs, done after; after a fix round Fix's, after a rebuild Land's,
      # lintFix: now while it runs); the landing gate's is a Fix round (lintFix: now on Fix while it runs). lg: the gate of the start in progress, else null; lk: that gate, kept until its fix line.
      | (reduce $log[] as $l ({s: [range(6) | {state: "todo", sec: null}], cur: null, rev: 0, fix: 0, pushed: false, issue: null, closed: false, filed: null, last: 0, prev: null, rc: false, lg: null, lk: null};
          def add($i): .s[$i].sec = (.s[$i].sec // 0) + ($l.took // 0) | .cur = $i;
          .rc = ($l.step == "start" and $l.of == "fix" and .prev.checkFailed == true)
          | .lg = (if $l.step == "start" and $l.of == "fix" and .prev.step == "lint" and .prev.result == "findings" then .prev.gate // null else null end)
          | .lk = (.lg // .lk)
          | if $l.step | IN("worktree", "deps", "brief") then add(0)
          elif $l.step == "build" then add(0) | .s[0].state = "done" | .last = 0
          elif $l.step == "review" then add(1) | .s[1].state = "done" | .rev += 1
          elif $l.step == "fix" and .lk == "review" then add(.last) | if .last == 0 then .s[0].lintFix = "done" else . end
          elif $l.step == "fix" and ($l.reason | type == "string" and startswith("the Done-when check failed")) then add(.last) | if .last == 0 then .s[0].replyFix = "done" else . end
          elif $l.step == "fix" then add(2) | .s[2].state = "done" | .fix += 1 | .last = 2
          # Tests that failed are run again after their fix: the step is to come again, not failed. Tests that passed
          # only when the cases that did not pass ran again (tests()) are drawn so (rerun), never as a plain pass; a line
          # that reused a pass (card(): reused) keeps what the pass it reused was.
          # Its runs' seconds waiting for a test slot and running, added up (a line that does not give them adds none).
          # runs: the runs the lines record; a line with rerun (tests() ran the failed cases again at once) is two.
          elif $l.step == "test" then add(3) | .runs = (.runs // 0) + (if $l.rerun != null then 2 else 1 end) | .s[3].state = (if $l.result == "pass" then "done" else "todo" end)
            | .s[3].rerun = (if $l.result == "pass" and $l.reused == true then .s[3].rerun == true else $l.result == "pass" and $l.rerun != null end)
            | if ($l.wait | type) == "number" and ($l.run | type) == "number" then .s[3].wait = (.s[3].wait // 0) + $l.wait | .s[3].run = (.s[3].run // 0) + $l.run else . end
          # The landing that met a conflict ran until the rebuild began: those seconds are the landing's.
          elif $l.step == "start" and $l.of == "split" then .
          elif $l.step == "start" then (if $l.of == "rebase" then add(4) else . end) | .cur = (if .rc or .lg == "review" then .last else {build: 0, review: 1, fix: 2, test: 3}[$l.of] // 4 end)
          elif $l.step == "rebase" then add(4) | .last = 4
          elif $l.step == "filed" then add(4) | .filed = ($l.n // 0)
          elif $l.step == "landed" then add(4) | .s[4].state = "done"
          elif $l.step == "closed" then .closed = true
          elif $l.step == "pushed" then add(5) | .pushed = true
          elif $l.step == "issue" then add(5) | .issue = $l.result
          elif $l.step == "blocked" then ({worktree: 0, deps: 0, brief: 0}[$l.stop // ""] // .cur // 0) as $i
            | if $l.stop == "yes" then . else .s[$i].sec = (.s[$i].sec // 0) + ($l.took // 0) | .s[$i].state = "failed" end
          else . end | .prev = $l | if $l.step == "fix" then .lk = null else . end)) as $u
      | (if $after == "wait" then null elif $after then 5 elif $c.result != "" then null elif $kind == null then 0 elif $kind == "fix" and ($u.rc or $u.lg == "review") then $u.cur
         else {build: 0, proof: 0, review: 1, fix: 2, test: 3}[$kind] // 4 end) as $six
      # Push is done once main is pushed and the issue is closed: by GitHub (an issue line that is ok), or found closed
      # (x.shut) after GitHub did not close it, closed by hand; it stays failed only while the issue is open.
      | ($u.s | .[5].state = (if $u.closed or ($u.pushed and ($u.issue == "ok" or $c.issue == 0 or $c.x.shut == true)) then "done"
          elif $u.issue != null and $u.issue != "ok" then "failed" else "todo" end)
          | if $six == null then . else .[$six].state = (if $after | IN("pushfail", "pushheld", "issuefail") then "failed" else "now" end) end) as $s6
      | ([$six // -1, ($s6 | to_entries | map(select(.value.state != "todo") | .key) | max // -1)] | max) as $top
      # Why the push step failed: the push of main (its error), or GitHub kept the issue open ("GitHub did not close
      # the issue", then what the issue line says).
      | (if $after | IN("pushfail", "pushheld") then ($perr // "the push of main failed") elif $s6[5].state == "failed" then ([$log[] | select(.step == "issue")] | last
           | if . == null then "GitHub did not close the issue: no close of it was recorded"
             else .reason // "" | "GitHub did not close the issue" + (if . == "" then "" else ": \(.)" end) end) else null end) as $why
      | {steps: [range(6) as $i | $s6[$i] | {name: ["Build", "Review", "Fix", "Test", "Land", "Push"][$i],
            # Land is skipped only on a card closed unlanded.
            state: (if .state == "todo" and $i < $top and ($i != 4 or $u.closed) then "skipped" else .state end), sec}
          + (if $i == 0 and $six == 0 and $u.rc then {replyFix: "now"} elif $i == 0 and .replyFix != null then {replyFix} else {} end)
          + (if $i == 0 and $six == 0 and $kind == "fix" and $u.lg == "review" then {lintFix: "now"} elif $i == 0 and .lintFix != null then {lintFix} else {} end)
          # A lint fix on Fix (the landing gate's, or the review gate's after a fix round) or on Land (the review gate's
          # after a rebuild).
          + (if ($i == 2 or $i == 4) and $six == $i and $kind == "fix" and $u.lg != null then {lintFix: "now"} else {} end)
          + (if $i == 1 then {n: ($u.rev + (if $six == 1 then 1 else 0 end)), of: $of}
             elif $i == 2 then {n: ($u.fix + (if $six == 2 and ($u.rc | not) and $u.lg != "review" then 1 else 0 end))}
             # A running Test step: n, the run that goes now (its sec is the earlier runs' seconds, added up: #433). A
             # run again of the failed cases in the same step (the live record's before, session.sh watch()) is one
             # more, and the first run's seconds are in sec: no test line has them yet.
             elif $i == 3 then (if .wait != null then {wait, run} else {} end) + (if .rerun == true and .state == "done" then {rerun: true} else {} end)
               + (if $six == 3 then ($c.live.before | if $kind == "test" and type == "number" then . else null end) as $b
                   | {n: (($u.runs // 0) + 1 + (if $b == null then 0 else 1 end))} + (if $b == null then {} else {sec: ((.sec // 0) + $b)} end) else {} end)
             elif $i == 5 and $u.filed != null then {followups: $u.filed} else {} end)],
         at: $six, label: $label, since: (if $at == null then null elif $kind == "proof" then ($c.proof.at | strings) // $last.time else ($c.live.at | strings) // $last.time end),
         reason: $why,
         # How the card took up its issue's kept patch, as its worktree line says ("resumed from the kept patch of card
         # <card>: ...", or why it was built from nothing); null for a card whose worktree line gives no reason.
         kept: ([$log[] | select(.step == "worktree") | .reason // "" | select(. != "")] | first),
         # The card split for its size (growcheck(), lib/slices.sh): the files of its change before and after; else null.
         grown: ([$log[] | select(.step == "grown" and .grown.after != null) | .grown] | last | if . == null then null else {before: .files, after} end),
         files: (if $kind == "test" then ($c.live // {} | .files // null) elif $kind == "proof" then $c.proof.files else null end),
         tests: (if $kind == "test" then ($c.live // {} | .tests // null) elif $kind == "proof" then $c.proof.tests else null end),
         # The list of tests the run was given (tests()): {mode: "changed", files, by, age} or {mode: "whole", why}.
         list: (if $kind == "test" then ($c.live // {} | .list // null) elif $kind == "proof" then $c.proof.list else null end),
         # The 17 steps the track once had, each with its seconds added up.
         detail: ($detail | if $c.x.shut == true and .[15].state == "failed" then .[15].state = "done" else . end), detailAt: $at,
         # Every recorded step, one for each line of the card in the order they were written, with its own seconds
         # (the card opens to show them): a failed test run, its fix, the review after it and the tests again are each
         # their own step. The step in progress, if any, is the last. at is when a step ended (its line's time; the
         # queue's ends at the pick-up), so the Board draws each on a time axis; a review has its counts (findings by level) and its judge (as in reviews).
         records: ([{name: "queued", state: "done", sec: (($log[0] // {}) | try ((.time | fromdate) - (.created | fromdate)) catch null), at: ($log[0].time // null)}]
           + [$log | to_entries[] | .key as $k | .value as $l
              | select($l.step != "start" or $l.of == "rebase")
              | ([$log[:$k][] | select(.step == $l.step)] | length + 1) as $nth
              | {name: (if $l.step == "picked" then "picked" elif $l.step == "worktree" then "worktree ready" elif $l.step == "deps" then "dependencies linked"
                  elif $l.step == "brief" then "brief written" elif $l.step == "build" then "building"
                  elif $l.step == "review" then "review \($nth)" + (if ($l.result // "") == "" then "" else " (\($l.result))" end)
                  elif $l.step == "fix" then "fix \($nth)" elif $l.step == "test" then "tests " + (if $l.result == "pass" then "passed" elif $l.result == "held" then "held: the machine" else "failed" end)
                  elif $l.step == "start" then "landing (met a conflict)" elif $l.step == "rebase" then "rebuild" elif $l.step == "landed" then "landing"
                  elif $l.step == "closed" then "landing (issue closed)"
                  # A push that went on over a pre-push hook that failed naming test files that each passed alone (pushone()).
                  elif $l.step == "pushed" then "pushed" + (($l.flaky | objects | " (flaky: passed alone: \(.files | join(", ")))") // "")
                  elif $l.step == "push" then (if $l.result == "ok" then "push" else "push failed" end)
                  elif $l.step == "issue" then (if $l.result == "ok" then "issue closed" else "issue not closed" end)
                  elif $l.step == "filed" then "follow-ups filed" elif $l.step == "blocked" then "stopped"
                  elif $l.step == "grown" then (if $l.grown.after != null then "split for its size: \($l.grown.files) files, \($l.grown.after) after"
                    elif $l.result == "split" then "would split for its size: \($l.grown.files) files" else "kept at its size: \($l.grown.files) files" end)
                  else $l.step end),
                 state: (if ($l.step == "test" and $l.result == "fail") or ($l.step == "issue" and $l.result != "ok") or ($l.step == "review" and ($l.result | IN("fail", "stopped")))
                   or ($l.step == "blocked" and $l.stop != "yes") then "failed" else "done" end),
                 sec: (if $l.step == "picked" then null else $l.took // null end), at: $l.time}
                # A filed line's outside: the findings the judge found outside the card's change, each {finding, issue}.
                + (if $l.step == "filed" then {n: ($l.n // 0)} + (if $l.outside then {outside: $l.outside} else {} end) elif $l.step == "review" then {counts: ($l.counts // null), judge: ($l.judge // null)}
                   elif $l.step == "test" and $l.result == "pass" and $l.rerun != null then {rerun: true} else {} end)
                # A blocked line's sentence (why) and the end of its output, a failed test run's, review's or issue closing's reason (why),
                # a worktree line's reason (why: how the card took up a kept patch), a lint line's reason (why: each
                # command's result and seconds, `skipped: missing <tool>`, `tools ran as installed`), a NO-GO review's findings (output), a failed test run's failing files (failures) and the end of its output, and a
                # fix's reason: what started it when its line names it (a failed Done-when check, main moved), as the Board labels it.
                + ({why: (if $l.step == "blocked" or ($l.step == "test" and $l.result != "pass") or ($l.step == "issue" and $l.result != "ok")
                      or ($l.step == "review" and ($l.result | IN("fail", "stopped"))) or $l.step == "worktree" or $l.step == "lint" then $l.reason
                      # A test run that left linked test files out (testcap(), testrun.sh), or ran only the changed
                      # cases of its own test files (owncases(), testlist.sh): its list's note (rows.jq) says so.
                      elif $l.step == "test" and $l.list != null then $l.list.why else null end),
                    # A GO review's findings too when the judge found one outside the card's change (an OUTSIDE line of its tail, rows.jq).
                    output: (if $l.step == "blocked" or ($l.step == "test" and $l.result != "pass") or ($l.step == "review" and $l.result == "NO-GO") then $l.tail
                      elif $l.step == "review" and ($l.tail // "" | test("(^|\n)(OUTSIDE|SELFHEALS): ")) then $l.tail else null end),
                    failures: (if $l.step == "test" and $l.result != "pass" then $l.failures else null end),
                    # A test run's changed lines no test reached, from its coverage report (uncovered(), testlist.sh).
                    coverage: (if $l.step == "test" then $l.coverage else null end),
                    reason: (if $l.step == "fix" then $l.reason else null end),
                    # A build, fix or rebase line whose Done-when check failed items (rows.jq checkFailed): the Board
                    # names the fix that starts next the reply check's, as the six steps do (rc), and no other one so.
                    checkFailed: $l.checkFailed,
                    # A lint line's gate (rows.jq gate): the Board numbers the lint fix after it as the six steps do.
                    gate: (if $l.step == "lint" then $l.gate else null end),
                    # A lint line's commands, {n, run, result, sec, findings}: the Board shows a row a command in place of the reason.
                    lint: (if $l.step == "lint" and ($l.lintCommands | length) > 0 then $l.lintCommands else null end)}
                   | with_entries(select(.value != null and .value != "")))]
           + (if $label == "" or $after == "wait" then [] else [{name: $label, sec: null} + (if $after | IN("pushfail", "pushheld", "issuefail")
               # A failed push or close of the issue: when it was last seen (the last line's time) and why, as the push step says.
               then {state: "failed", at: $last.time, why: $why} | with_entries(select(.value != null and .value != "")) else {state: "now"} end)] end))};

