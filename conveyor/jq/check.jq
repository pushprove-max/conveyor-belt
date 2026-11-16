# check() in conveyor.sh: the number of every line that is not one whole record of a known step.
def fails: type == "object" and keys == ["files", "of", "timeout"] and (.of | . == null or type == "number")
  and (.files | type == "array" and all((.file | type == "string") and (.cases | type == "array" and all(keys == ["line", "name"] and all(type == "string")))))
  and (.timeout | . == null or (type == "object" and keys == ["file", "sec"]));
[inputs] | to_entries[] | select(.value | (try (fromjson
      | (keys - ["product", "title", "usage", "kept", "leftover", "followups", "sec", "visible", "branch", "created", "counts", "of", "model", "effort",
          "stats", "tests", "diff", "limit", "depth", "spent", "unread", "retriedAt", "head", "yesFrom", "paths", "pid", "started", "tail", "firstTry", "doneWhen", "batch", "failures", "rerun", "repo", "account", "reviewAccount", "engine", "stalls", "judge", "patch", "main", "seen", "reused", "cost",
          "wait", "run", "slotsFree", "selected", "ended", "slow", "timed", "times", "clocks", "kind", "check", "why", "wholeSuite", "ranCases", "verdicts", "mainRun", "refused", "mainRed", "beyond", "speed", "testedits", "route"]) ==["card", "issue", "reason", "result", "sha", "step", "time", "tokens"]
        and ([.card, .result, .sha, .reason] | all(type == "string")) and (.issue | type == "number")
        and (.time | fromdate | type == "number") and (.tokens | keys == ["claude", "codex"] and all(type == "number"))
        and (.step | IN("picked", "worktree", "deps", "brief", "start", "build", "review", "test", "fix", "rebase", "filed", "landed", "closed", "blocked", "push", "pushed", "issue", "bugproof"))
        # A bugproof line: the bug-card check was skipped (bugproof()), its reason saying why; or a speed-up card's check
        # held (ok) or not (fail), with its file's CPU seconds on record and now (speedproof(), optproof()), and the fix
        # it made with the test files it added or changed (a line written before the fix was recorded has neither).
        and (.step != "bugproof" or (.result == "skipped" and .speed == null) or ((.result | IN("ok", "fail"))
          and (.speed | type == "object" and (.file | type == "string") and ([.before, .after] | all(. == null or type == "number"))
            and (keys == ["after", "before", "file"] or (keys == ["after", "before", "file", "fix", "into"]
              and (.fix | IN("sped up", "split", "merged", "deleted")) and (.into | type == "array" and all(.[]; type == "string")))))))
        and (.speed == null or .step == "bugproof")
        and (.step != "start" or (.of | IN("build", "review", "fix", "test", "file", "land", "rebase")))
        and (.counts // {P0: 0, P1: 0, P2: 0, P3: 0} | type == "object" and keys == ["P0", "P1", "P2", "P3"] and all(type == "number"))
        and (.created // "" | type == "string")
        and (.step != "landed" or ((.sha | length) > 0 and (.product | type == "boolean")))
        and (.followups // [] | type == "array" and all(type == "number"))
        and (.visible // "" | type == "string") and (.branch // "" | type == "string") and (.mainRed // "" | type == "string")
        and (.model // "" | type == "string") and (.effort // "" | type == "string") and (.head // "" | type == "string") and (.unread // "" | type == "string")
        and (.patch // "" | type == "string") and (.main // "" | type == "string") and (.seen // "" | type == "string")
        # route: the route a Claude or Codex session took when a proxy is set (session1(), claudereview(), codexreview()).
        and (.route // "proxy" | IN("proxy", "subscription"))
        # reused: a test line's says it reused a pass (true); a review line's is the time of the review it reuses.
        and (if .step == "test" then (.reused // false | type == "boolean") else (.reused // "2000-01-01T00:00:00Z" | fromdate | type == "number") end)
        and (.retriedAt // "2000-01-01T00:00:00Z" | fromdate | type == "number")
        # cost: the dollars an OpenCode review's own usage report gave (OCREVIEWREAD).
        and (.sec // 0 | type == "number") and (.cost // 0 | type == "number") and (.limit // 0 | type == "number") and (.depth // 0 | type == "number") and (.yesFrom // 0 | type == "number") and (.stalls // 0 | type == "number")
        and (.paths // [] | type == "array" and all(type == "string")) and (.batch // [] | type == "array" and all(type == "string"))
        and (.pid // 0 | type == "number") and (.repo // "" | type == "string") and (.started // "" | type == "string") and (.tail // "" | type == "string")
        and (.account // "" | type == "string") and (.reviewAccount // "" | type == "string") and (.engine // "" | type == "string")
        and (.stats // {} | type == "object") and (.judge // {} | type == "object") and (.firstTry // {} | type == "object") and (.spent // {step: "build"} | type == "object" and (.step | IN("build", "fix", "rebase", "review")))
        and (.tests // {} | type == "object" and all(. == null or type == "number"))
        and ([.wait, .run, .slotsFree] | all(. == null or type == "number"))
        and (.selected // {files: null, filesOf: null, cases: null, casesOf: null} | type == "object" and keys - ["kept"] == ["cases", "casesOf", "files", "filesOf"] and all(. == null or type == "number"))
        and (.ended // "passed" | IN("passed", "failed", "killed", "timed out", "nothing selected"))
        # The test files over the CPU budget (slowtests()): before and finding only of a file the card changed; no cpu
        # on a line written while the budget was clock seconds, which the records still hold.
        and (.slow // [] | type == "array" and all(type == "object" and (.file | type == "string") and ([.sec, .budget, .cpu // 0] | all(type == "number"))
          and (.changed | type == "boolean") and (.before // 0 | type == "number") and (.finding // false | type == "boolean")
          and (.from // "" | type == "string") and (keys - ["before", "finding", "cpu", "from"] == ["budget", "changed", "file", "sec"])))
        # The CPU seconds of every test file the run timed (slowtests()), {file: cpu}: a later card's before.
        and (.times // {} | type == "object" and all(type == "number"))
        # The clock seconds of the same files (slowtests()), {file: sec}: the snapshot's tests part.
        and (.clocks // {} | type == "object" and all(type == "number"))
        # Why each test file ran (testrec()), {file: [reasons]}; wholeSuite: the run ran every engine case file.
        and (.why // {} | type == "object" and all(type == "array" and all(type == "string")))
        and (.wholeSuite // true | . == true)
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
        and (.verdicts // [] | type == "array" and all(type == "object" and keys == ["case", "verdict"] and (.case | type == "string") and (.verdict | IN("card", "main", "flaky"))))
        and (.mainRun // {sha: "", sec: 0, exit: 0} | type == "object" and keys == ["exit", "sec", "sha"] and (.sha | type == "string") and ([.sec, .exit] | all(type == "number")))
        # A run that went again (tests()): the first run's exit and failures.
        and (.rerun // {exit: 1, failures: {of: null, files: [], timeout: null}} | type == "object" and keys == ["exit", "failures"] and (.exit | type == "number") and (.failures | fails))
        and (.doneWhen // {items: 0, met: 0, failed: []} | type == "object" and (keys - ["notes"]) == ["failed", "items", "met"]
          and (.items | type == "number") and (.met | type == "number") and (.failed | type == "array" and all(type == "string"))
          and ((has("notes") | not) or (.notes | type == "array" and all(type == "string"))))
        # What a landed card did to the test files main had (testedits()): counts null on a file it could not read.
        and (.testedits // [] | type == "array" and all(type == "object" and keys == ["casesDeleted", "changedExpected", "file", "read", "removedAsserts", "skipsAdded", "timeoutsRaised"]
          and (.file | type == "string") and (.read | type == "boolean") and (.read as $read
          | [.removedAsserts, .changedExpected, .skipsAdded, .timeoutsRaised, .casesDeleted] | all(if $read then type == "number" else . == null end))))
        and (.diff // {files: 0, added: 0, removed: 0} | type == "object" and keys == ["added", "files", "removed"] and all(type == "number"))) catch false) | not)
    | .key + 1
