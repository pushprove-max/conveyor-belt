# check() in views.sh: every line that is not one whole record of a known step, as `<line number> TAB <field>`: the
# field the check refused (one not in the list below, a required one missing, or the first whose value it refuses),
# "(not JSON)", "(not an object)", or "step" when only the fields together are refused for that step.
def fails: type == "object" and keys == ["files", "of", "timeout"] and (.of | . == null or type == "number")
  and (.files | type == "array" and all((.file | type == "string") and (.cases | type == "array" and all(keys == ["line", "name"] and all(type == "string")))))
  and (.timeout | . == null or (type == "object" and keys == ["file", "sec"]));
def need: ["card", "issue", "reason", "result", "sha", "step", "time", "tokens"];
def known: ["product", "title", "usage", "kept", "leftover", "followups", "sec", "visible", "branch", "created", "counts", "of", "model", "effort",
  "stats", "tests", "diff", "limit", "depth", "spent", "unread", "retriedAt", "head", "yesFrom", "paths", "pid", "started", "tail", "firstTry", "doneWhen", "doneWhenItems", "doneWhenHolds", "excerpts", "batch", "failures", "rerun", "repo", "account", "reviewAccount", "engine", "stalls", "judge", "patch", "main", "seen", "reused", "cost", "survived", "answers",
  "wait", "run", "slotsFree", "selected", "ended", "list", "coverage", "slow", "timed", "times", "clocks", "carried", "kind", "check", "why", "wholeSuite", "ranCases", "verdicts", "mainRun", "refused", "mainRed", "beyond", "speed", "testedits", "route", "speedcheck", "retriedWhy", "waitSec", "wide", "pr", "doneLines", "ran", "checks", "split", "grown", "rollout", "pick"];
def steps: ["picked", "split", "worktree", "deps", "brief", "start", "build", "review", "test", "fix", "rebase", "filed", "landed", "closed", "blocked", "push", "pushed", "issue", "bugproof", "grown"];
# Each required field's own test.
def needok($k): if $k == "issue" then .issue | type == "number" elif $k == "time" then (try (.time | fromdate | type == "number") catch false)
  elif $k == "tokens" then .tokens | type == "object" and keys == ["claude", "codex"] and all(type == "number")
  elif $k == "step" then .step | IN(steps[]) else .[$k] | type == "string" end;
def ok: . as $r | (keys - known) == need
        and all(need[]; . as $k | $r | needok($k))
        # A bugproof line: the bug-card check was skipped (bugproof()), its reason saying why; or a speed-up card's check
        # held (ok) or not (fail), with its file's CPU seconds on record and now (speedproof(), optproof()), and the fix
        # it made with the test files it added or changed (a line written before the fix was recorded has neither); or
        # test.command, given the check's test files, ran far more (wide: {given, ran, command}).
        and (.wide == null or (.step == "bugproof" and .result == "wide" and (.wide | type == "object" and keys == ["command", "given", "ran"]
          and (.command | type == "string") and ([.given, .ran] | all(type == "number")))))
        and (.step != "bugproof" or (.result == "skipped" and .speed == null) or (.result == "wide" and .speed == null and .wide != null) or ((.result | IN("ok", "fail"))
          and (.speed | type == "object" and (.file | type == "string") and ([.before, .after] | all(. == null or type == "number"))
            and (keys == ["after", "before", "file"] or (keys == ["after", "before", "file", "fix", "into"]
              and (.fix | IN("sped up", "split", "merged", "deleted")) and (.into | type == "array" and all(.[]; type == "string")))))))
        and (.speed == null or .step == "bugproof")
        and (.step != "start" or (.of | IN("build", "review", "fix", "test", "file", "land", "rebase")))
        and (.counts // {P0: 0, P1: 0, P2: 0, P3: 0} | type == "object" and keys == ["P0", "P1", "P2", "P3"] and all(type == "number"))
        and (.created // "" | type == "string")
        and (.step != "landed" or ((.sha | length) > 0 and (.product | type == "boolean")))
        and (.followups // [] | type == "array" and all(type == "number"))
        # rollout: the rollout actions a review named, or a landed card carries (rollouts(), lib/prompts.sh).
        and (.rollout == null or ((.step | IN("review", "landed")) and (.rollout | type == "array" and length > 0
          and all(type == "object" and keys == ["action", "fails", "place"] and all(type == "string")))))
        and (.visible // "" | type == "string") and (.branch // "" | type == "string") and (.mainRed // "" | type == "string")
        and (.model // "" | type == "string") and (.effort // "" | type == "string") and (.head // "" | type == "string") and (.unread // "" | type == "string")
        and (.patch // "" | type == "string") and (.main // "" | type == "string") and (.seen // "" | type == "string")
        # route: the route a Claude or Codex session took when a proxy is set (session1(), claudereview(), codexreview()).
        and (.route // "proxy" | IN("proxy", "subscription"))
        # reused: a test line's says it reused a pass (true); a review line's is the time of the review it reuses.
        and (if .step == "test" then (.reused // false | type == "boolean") else (.reused // "2000-01-01T00:00:00Z" | fromdate | type == "number") end)
        and (.retriedAt // "2000-01-01T00:00:00Z" | fromdate | type == "number")
        # speedcheck: the version of the speed check that blocked the card; retriedWhy: why the loop retried it itself.
        and (.speedcheck // 0 | type == "number") and (.retriedWhy // "" | type == "string")
        # waitSec: the seconds a landed or blocked card waited on other cards and for main to change (card(), block()).
        and (.waitSec // 0 | type == "number")
        # doneLines: the reply's D<n> lines on a session's line with a Done-when check (checked(), lib/testrun.sh).
        and (.doneLines // [] | type == "array" and all(type == "string"))
        # checks: a test line of a Test step the project's checks ended before any test ran (card(), treecheck()).
        and (.checks // true | . == true)
        # pr: the pull request a pushed line's push went into, with the rule Land as pr (pushone(), lib/push.sh).
        and (.pr // 0 | type == "number")
        # cost: the dollars an OpenCode review's own usage report gave (OCREVIEWREAD).
        and (.sec // 0 | type == "number") and (.cost // 0 | type == "number") and (.limit // 0 | type == "number") and (.depth // 0 | type == "number") and (.yesFrom // 0 | type == "number") and (.stalls // 0 | type == "number")
        and (.paths // [] | type == "array" and all(type == "string")) and (.batch // [] | type == "array" and all(type == "string"))
        and (.pid // 0 | type == "number") and (.repo // "" | type == "string") and (.started // "" | type == "string") and (.tail // "" | type == "string")
        and (.account // "" | type == "string") and (.reviewAccount // "" | type == "string") and (.engine // "" | type == "string")
        and (.stats // {} | type == "object") and (.judge // {} | type == "object") and (.firstTry // {} | type == "object") and (.spent // {step: "build"} | type == "object" and (.step | IN("build", "fix", "rebase", "review")))
        and (.tests // {} | type == "object" and all(. == null or type == "number"))
        # A NO-GO review's findings that came back after a fix round (card.sh): each its id and how many fix rounds.
        and (.survived // [] | type == "array" and all(.[]; type == "object" and (.id | type == "string") and (.rounds | type == "number")))
        # A review's answers on the findings fix rounds were told (card.sh, answers()): each its id, answer and first record.
        and (.answers // [] | type == "array" and all(.[]; type == "object" and (.id | type == "string") and (.answer | type == "string") and (.first | type == "object")))
        and ([.wait, .run, .slotsFree] | all(. == null or type == "number"))
        and (.selected // {files: null, filesOf: null, cases: null, casesOf: null} | type == "object" and keys - ["kept"] == ["cases", "casesOf", "files", "filesOf"] and all(. == null or type == "number"))
        and (.ended // "passed" | IN("passed", "failed", "killed", "timed out", "nothing selected"))
        # How a test step's first run picked its files (testlist(), testrun.sh): the whole suite and why, or the
        # changed tests, how many and by what (the test map or names), with the map's age when known.
        and (.list // {mode: "whole", why: ""} | type == "object" and ((.mode == "whole" and (.why | type == "string"))
          or (.mode == "changed" and (.files | type == "number") and (.by | type == "string") and (.age // 0 | type == "number"))))
        # The changed lines no test reached, from the run's coverage report (uncovered(), testrun.sh), or why unknown.
        and (.coverage // {unknown: ""} | type == "object" and (if has("unknown") then keys == ["unknown"] and (.unknown | type == "string")
          else keys == ["checked", "count", "uncovered"] and ([.count, .checked] | all(type == "number"))
            and (.uncovered | type == "array" and all(type == "object" and keys == ["file", "lines"] and ([.file, .lines] | all(type == "string")))) end))
        # The test files over the CPU budget, on a line written while test files had one (none is written now, #349):
        # before and finding only of a file the card changed; no cpu on a line written while the budget was clock
        # seconds. The records still hold such lines.
        and (.slow // [] | type == "array" and all(type == "object" and (.file | type == "string") and ([.sec, .budget, .cpu // 0] | all(type == "number"))
          and (.changed | type == "boolean") and (.before // 0 | type == "number") and (.finding // false | type == "boolean")
          and (.from // "" | type == "string") and (keys - ["before", "finding", "cpu", "from"] == ["budget", "changed", "file", "sec"])))
        # The CPU seconds of every test file the run timed (slowtests()), {file: cpu}: a later card's before.
        and (.times // {} | type == "object" and all(type == "number"))
        # The clock seconds of the same files (slowtests()), {file: sec}: the snapshot's tests part.
        and (.clocks // {} | type == "object" and all(type == "number"))
        # The files an earlier step timed and this one kept as passed, not run (carriedrec()).
        and (.carried // [] | type == "array" and all(type == "string"))
        # Why each test file ran (testrec()), {file: [reasons]}; wholeSuite: the run ran every engine case file.
        and (.why // {} | type == "object" and all(type == "array" and all(type == "string")))
        and (.wholeSuite // true | . == true)
        # The files a run began (testrec()): why may name files it kept off.
        and (.ran // [] | type == "array" and all(type == "string"))
        # The cases a run of only part of a file selected (testrec()), {file: [cases]}.
        and (.ranCases // {} | type == "object" and all(type == "array" and all(type == "string")))
        # A full run the test step refused (tests()): "refused full run: <why>".
        and (.refused // "refused full run: " | type == "string" and startswith("refused full run: "))
        # A picked line's slot beyond the cap (pick(): a main-red fix, issue 612): why it took one.
        and (.beyond // "main is red" | . == "main is red")
        # The times of the test files the card changed (slowtests()): cpu null when the runner gave none.
        and (.timed // [] | type == "array" and all(type == "object" and keys == ["cpu", "file", "sec"] and (.file | type == "string")
          and (.sec | type == "number") and (.cpu | . == null or type == "number")))
        # A failed push line's kind (push()): its check failed, or anything else did; a check failure names the check.
        and (.kind // "transport" | IN("check", "transport")) and (.check // "" | type == "string")
        and (.failures // {of: null, files: [], timeout: null} | fails)
        # Each failure's verdict (verdicts()), and the run of the failing cases on main.
        and (.verdicts // [] | type == "array" and all(type == "object" and keys == ["case", "verdict"] and (.case | type == "string") and (.verdict | IN("card", "main", "machine", "flaky"))))
        and (.mainRun // {sha: "", sec: 0, exit: 0} | type == "object" and keys == ["exit", "sec", "sha"] and (.sha | type == "string") and ([.sec, .exit] | all(type == "number")))
        # A run that went again (tests()): the first run's exit and failures, and the end of its output.
        and (.rerun // {exit: 1, failures: {of: null, files: [], timeout: null}} | type == "object" and (keys - ["tail"]) == ["exit", "failures"] and (.exit | type == "number") and (.failures | fails)
          and (.tail // "" | type == "string"))
        and (.doneWhen // {items: 0, met: 0, failed: []} | type == "object" and (keys - ["notes"]) == ["failed", "items", "met"]
          and (.items | type == "number") and (.met | type == "number") and (.failed | type == "array" and all(type == "string"))
          and ((has("notes") | not) or (.notes | type == "array" and all(type == "string"))))
        # Each Done-when item of the check (donewhen()): the issue's text and the reply's D<n> line; and the D<n> a review
        # said hold (its DONE-WHEN lines).
        and (.doneWhenItems // [] | type == "array" and all(type == "object" and keys == ["n", "said", "text"] and (.n | type == "number")
          and (.text | type == "string") and (.said | . == null or type == "string")))
        and (.doneWhenHolds // [] | type == "array" and all(type == "number"))
        # The lines a review's findings cite, from the tree it read (excerpts(), lib/review.sh).
        and (.excerpts // [] | type == "array" and all(type == "object" and keys == ["at", "from", "lines", "side"]
          and (.at | type == "string") and (.from | type == "number") and (.side == "new" or .side == "old" or .side == "fix")
          and (.lines | type == "array" and all(type == "string"))))
        # What a landed card did to the test files main had (testedits()): counts null on a file it could not read.
        and (.testedits // [] | type == "array" and all(type == "object" and keys == ["casesDeleted", "changedExpected", "file", "read", "removedAsserts", "skipsAdded", "timeoutsRaised"]
          and (.file | type == "string") and (.read | type == "boolean") and (.read as $read
          | [.removedAsserts, .changedExpected, .skipsAdded, .timeoutsRaised, .casesDeleted] | all(if $read then type == "number" else . == null end))))
        and (.diff // {files: 0, added: 0, removed: 0} | type == "object" and keys == ["added", "files", "removed"] and all(type == "number"))
        # A split line (splitcheck(), lib/slices.sh): kept or split, the rule's setting, the issue's text and size,
        # the verdict and why, the slices of a split, the issues filed for them and whether they started held (On), the
        # answer that broke the rules.
        # A card's pick (modelpick(), lib/modelpick.sh), on each of its lines from the pick on: its group, the
        # builder chosen, by whom, whether it is a trial, and the rule's setting; on a trial card, the pipeline files its
        # change touches (trialflag()), when there are any; on a card of a promoted group on the challenger
        # (pickpromote()), promoted: true; on a card of the rule On that is not a trial, the reviewer and judge seats
        # the owner promoted from a replay result (pickseats()), seats.
        and (.pick == null or (.pick | type == "object" and (keys - ["pipeline", "promoted", "seats"]) == ["by", "choice", "group", "mode", "trial"] and (.group | type == "string")
          and (.pipeline == null or (.trial and (.pipeline | type == "array" and length > 0 and all(type == "string"))))
          and ((has("promoted") | not) or (.promoted == true and .trial == false))
          and ((has("seats") | not) or (.trial == false and .mode == "on" and (.seats | type == "object" and length > 0 and all(keys[]; IN("reviewer", "judge"))
            and all(.[]; type == "object" and keys == ["effort", "model"] and all(.[]; type == "string")))))
          and (.choice | type == "object" and keys == ["effort", "model"] and (.model | type == "string") and (.effort == null or (.effort | type == "string")))
          and (.by | IN("owner", "auto")) and (.trial | type == "boolean") and (.mode | IN("shadow", "on"))))
        and ((.step == "split") == (.split != null))
        and (.split == null or ((.result | IN("kept", "split")) and (.split | type == "object"
          and (keys - ["slices", "filed", "held", "answer"]) == ["hash", "mode", "size", "verdict", "why"]
          and (.held // false | type == "boolean")
          and (.mode | IN("shadow", "on")) and ([.hash, .why, .answer // ""] | all(type == "string"))
          and (.verdict | IN("under", "keep", "split", "invalid", "failed")) and ((.verdict == "split") == ($r.result == "split"))
          and (.size | type == "object" and keys == ["areas", "chars", "doneWhen", "files"] and all(type == "number"))
          and (.slices // [] | type == "array" and all(type == "object" and keys == ["covers", "dependsOn", "doneWhen", "title"] and (.title | type == "string")
            and ([.covers, .dependsOn] | all(type == "array" and all(type == "number"))) and (.doneWhen | type == "array" and all(type == "string"))))
          and (.filed // [] | type == "array" and all(type == "number")))))
        # A grown line (growcheck(), lib/slices.sh): a change past split.growFiles files, the judge's verdict on it, the
        # slices of a split, the issues filed for them and the files left (On), the answer that broke the rules.
        and ((.step == "grown") == (.grown != null))
        and (.grown == null or ((.result | IN("kept", "split")) and (.grown | type == "object"
          and (keys - ["core", "slices", "filed", "after", "answer"]) == ["files", "limit", "mode", "verdict", "why"]
          and (.mode | IN("shadow", "on")) and ([.why, .answer // ""] | all(type == "string")) and ([.files, .limit, .after // 0] | all(type == "number"))
          and (.verdict | IN("keep", "split", "invalid", "failed")) and ((.verdict == "split") == ($r.result == "split"))
          and (.core // [] | type == "array" and all(type == "string"))
          and (.slices // [] | type == "array" and all(type == "object" and keys == ["dependsOn", "doneWhen", "files", "title"] and (.title | type == "string")
            and (.dependsOn | type == "array" and all(type == "number")) and ([.doneWhen, .files] | all(type == "array" and all(type == "string")))))
          and (.filed // [] | type == "array" and all(type == "number")))));
def good: try ok catch false;
# The field refused: one the list does not know, then a required one missing, then the first other field whose removal
# makes the record pass, then the first required one whose own test fails; else the step, whose fields together fail.
def why: if type != "object" then "(not an object)" else . as $r
  | first((keys - known - need)[], (need - keys)[], ((keys - need)[] | select(. as $k | $r | del(.[$k]) | good)),
      (need[] | select(. as $k | $r | needok($k) | not)), "step") end;
[inputs] | to_entries[] | (.key + 1) as $n | (try (.value | fromjson | {r: .}) catch null)
  | if . == null then "\($n)\t(not JSON)" elif .r | good then empty else "\($n)\t\(.r | why)" end
