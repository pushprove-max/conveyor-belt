# Shared CLI stubs

One stub for each CLI the engine tests fake: `claude`, `codex`, `opencode`, `gh`. `tests/lib.sh` copies them into each
case's `$STUB` and puts that folder first on `PATH`. A case sets what a stub answers with files in `$STUB`; the header
of each stub lists them. `clicontract.test.sh` runs the engine's own reading code against them.

A new test uses these stubs. A case that needs something the stub cannot do writes its own, with a comment saying why.

## Local stubs that stay

These files write their own `claude` or `codex` (with `cat >`, `printf >`, `mv`, into `$STUB` or a folder of their
own), each for what the shared stub cannot do:

- `apiroute.test.sh`: setup's own `PATH` folder (`$G`), whose `codex` only keeps its arguments.
- `cardseats.test.sh`: a judge seat (`--tools Read,Grep,Glob`) and a pick that keep their prompt, arguments and route.
- `clis.test.sh`: each CLI in a folder of its own, put on `PATH` or left off, and a `codex` that lists models.
- `codex.test.sh`: a Codex build that keeps its arguments, folder and prompt, runs the case's command, and can be a
  Codex whose help names no `--dangerously-bypass-hook-trust`.
- `deps.test.sh` (`t_overlapseat`): a same-file check that keeps its prompt and arguments.
- `donewhen.test.sh`, `merge.test.sh`: a session that answers `reply.<n>`, a different result for each session.
- `fail.test.sh`: reviews that fail with an API error, then answer.
- `judge.test.sh`: a judge seat that answers `judge.<n>`.
- `lane.test.sh`: a review that keeps the files staged when it ran.
- `metrics.test.sh` (`t_metricsfail`, `t_metricscut`, `t_metricsearly`): a session cut off by its timeout (exit 124,
  no result).
- `models.test.sh`: a Claude reviewer that writes in the worktree and keeps each prompt, and a `codex` that fails and
  says it ran.
- `proxyroute.test.sh`: calls that fail on the login and work only through the proxy, or that call the proxy.
- `records.test.sh` (`t_retryturn`): two sessions that wait for each other, by issue.
- `release.test.sh`, `releaseminver.test.sh`: a notes model that keeps its prompt and answers per call, a `claude`
  that fails, and the machine's own newer `claude`.
- `review.test.sh` (`t_chain`): a session that waits and fails for one issue and builds for another.
- `reviewacct.test.sh`: calls that keep the account they ran on, and a build that waits until the case lets it go.
- `rules.test.sh`: a `codex` taken off `PATH`.
- `setup.test.sh`: setup's own `PATH` folder (`$G`), whose `claude` installs plugins and `codex` does nothing.
- `stall.test.sh`: a review that hangs after its result.
- `swebenchshow.test.sh`: a benchmark's own `PATH` folder, whose `codex` keeps its arguments and fixes the task's files.
- `testaction.test.sh`, `testactqueue.test.sh`: a test action that streams its text, tries a write and `gh`, and
  waits until the case lets it go; a `codex` that lists a model.
- `transcript.test.sh`: a session that writes its transcript where Claude Code keeps it.

Other files edit the shared `codex` or `claude` in place (`sed -i`) to keep a prompt, the arguments or a key, or to
give a session a result text: the stub stays the shared one.
