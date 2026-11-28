# Contributing

Thank you for helping. Everyone taking part follows the [Code of conduct](CODE_OF_CONDUCT.md).

## Proposing a change

Open an issue, from one of the [issue forms](.github/ISSUE_TEMPLATE/), that says what is wrong or missing today and
what should change. The [engine reference](conveyor/README.md) says how the engine works. Conveyor Belt builds itself: an
accepted issue becomes a card, built, reviewed, tested and landed by the belt (README.md). A pull request is welcome
too; it is reviewed against the same rules.

The owner approves every change to how the engine builds, reviews, fixes, tests, lands or pushes (the pack's
`pipelineFiles`), whoever proposes it. The same rule is in the card rules every card is given
(`conveyor/rules/card-core.md`).

## Sign-off

Every commit in a pull request is signed off under the Developer Certificate of Origin, version 1.1 ([DCO](DCO)). The
sign-off says that you wrote the change, or have the right to submit it, under the project's license. Sign a commit
off with `git commit -s`: git adds a last line `Signed-off-by: Your Name <your email>` with your name and email
as the commit's author. To sign off commits you made already, run `git rebase --signoff <base>` and push again.

## Rules

- Every source file the project writes (shell, Python, JavaScript, TypeScript, CSS, HTML and the YAML under
  `.github/`) starts with `SPDX-License-Identifier: Apache-2.0` in that language's comment form, after the shebang
  or the HTML doctype where there is one. Vendored files keep their own license. `spdx.test.sh` fails, naming the
  file, on a source file without it.
- The smallest change that fully solves the issue; no feature flags, no compatibility code for old data.
- shellcheck is the linter of the shell files: the pack's `lint` field runs `.conveyor/lint-shell.sh` on each changed
  `.sh` file, and `bash .conveyor/test-changed.sh` fails on a warning on a line the change added or changed. A file
  with no `#!` line is read as bash.
- `.conveyor/lint-funcs.sh` is the function-length linter of the shell files: a shell function can have at most 100
  lines. A shell, Python, JavaScript or TypeScript file can have at most 800 lines (the pack's size entry; the files
  under `.claude/dashboard/vendor` are not counted). The pack's `lint` field runs both checks, and every finding of
  them counts, on any line. The exempt file `.conveyor/size-exempt.txt` names the files (`<path>`) that are over the
  file limit now, and the functions (`<path><TAB><name>`) that are over the function limit or that the linter cannot
  measure (`lint-funcs.sh --list` says `not measured`). A change that splits an exempt file or function so it is in
  the limit removes its line from the exempt file. The function-length entry's `files` name the exempt file and leave
  out `.conveyor/lint-funcs.sh`, `.conveyor/lint-shell.sh` and `.conveyor/lint-js.sh`: a change that only removes lines from a file those
  `files` match needs no owner's yes, which is right for the exempt file and wrong for a linter.
- ruff is the linter of the Python files: the pack's `lint` field runs `ruff check` on each changed `.py` file, read
  only (`--no-fix`). Its config, `ruff.toml`, keeps ruff's default rules and adds the complexity rules `C901` and
  `PLR0915`, with their limits. ruff is a tool of the build machine, not a dependency of the Board or the engine; with
  no ruff on `PATH`, the command is skipped as `missing ruff`. A change to `ruff.toml` is lint policy.
- ESLint is the linter of the Board's JavaScript: the pack's `lint` field runs `.conveyor/lint-js.sh` on each changed
  `.js` file under `.claude/dashboard` (not the files under `.claude/dashboard/vendor`), read only, and a warning is a
  finding too. Its config, `eslint.config.js`, keeps ESLint's recommended rules, adds the complexity rules
  `complexity`, `max-lines-per-function` and `max-depth`, with their limits, and names the globals the Board's files
  share. ESLint is a dev dependency in `package.json`; with no `node_modules/.bin/eslint` (`npm ci` installs it), the
  command is skipped as `missing eslint`. A change to `eslint.config.js` or `.conveyor/lint-js.sh` is lint policy.
- The engine is bash 5.1 and jq; the Board is Python 3's standard library unless an issue names a pinned library.
  Both run on macOS and Linux (`conveyor/lib/portable.sh`).
- The plugin is generic: no project's own names, paths or labels outside docs that name one as an example.
- This repository is public. No person's name, no email that is not a GitHub noreply address, no home path, no
  private host name or address goes into code, comments, tests, fixtures, docs or commit messages. A commit's
  author and its credit lines (such as `Co-Authored-By:`) are the exception: they may name a person. Fixtures use
  example.com addresses, `$HOME`-relative paths and 192.0.2.x addresses. The privacy check finds most of these:
  `git ls-files -z | xargs -0 bash conveyor/privacy/check.sh`.

## Tests

A test says why the behaviour matters and fails when it breaks; an existing test is never weakened to pass.

- The test lint (`.conveyor/test-lint.sh`, part of every `bash .conveyor/test-changed.sh` run) fails a test that
  sleeps a set time and then checks, and a full-loop run (`loop run`, `loop serve`, `conveyor.sh run` or
  `conveyor.sh serve`) on a line the change added or changed with no `# loop: <why>` comment on that line or the line
  above. The comment says what only a whole loop run shows. A line the change did not touch is not checked.
- A test waits for a file or a process with `wait_until` (`conveyor/tests/wait.sh`), and a script that an engine
  case writes waits with `wait_poll` (the text that `wait_fn` prints, `conveyor/tests/wait.test.sh`). Each has a
  ceiling and says what it waited for. The pack's `lint` field runs `.conveyor/lint-poll.sh` on the test files: a
  loop that waits for a file with only a pause (`until [ -e <file> ]; do sleep 0.1; done`) has no ceiling and is a
  finding.

- An engine test that needs a `claude`, `codex`, `opencode` or `gh` uses the shared stub in `conveyor/tests/stubs/`
  (`conveyor/tests/lib.sh` puts it on `PATH`), set by files in `$STUB`, and does not write its own: the stub answers
  in the form the engine reads, and `clicontract.test.sh` fails when the engine's reading and the stub part. A stub
  that must do what the shared one cannot says why in a `# stub: <why>` comment on the line that writes it or the
  line above: the test lint fails a line the change added or changed that writes a file named `claude`, `codex`,
  `opencode` or `gh` (with `>`, `>>`, `tee`, `cp`, `mv` or `install`) with no such comment. A file the shared stub
  reads, such as `$STUB/build`, is not a stub.

- `bash .conveyor/test-changed.sh` runs the tests of what you changed. For the engine, each engine file runs its own
  case files: its area of `.conveyor/engine-areas.json` names the case files under `conveyor/tests/` that exercise
  it, and a change to `conveyor/lib/review.sh`, say, runs only those. What every case runs through stays whole: a
  change to `conveyor/conveyor.sh`, `conveyor/conveyor.slowest`, `conveyor/tests/lib.sh`, `conveyor/tests/wait.sh`,
  `conveyor/lib/portable.sh`, `conveyor/lib/paths.sh` or the `conveyor/lib/test-*` files runs the whole engine test.
  A change to the map itself runs the map check, the map's own test (`.conveyor/test-changed.test.sh`) and the case
  files whose naming changed: each case file an area lists that it did not list at `HEAD`, and every case file of an
  area whose `files` list changed (the whole engine test if that area's tests are `"all"`, or if the map cannot be
  read at `HEAD` or in the worktree). A map edit that wrongly drops a case file from an area is not caught by the
  card; the map check and the whole suite are the net. A change in one engine file that breaks a case mapped only to
  another is found by the whole suite at the next release (`conveyor.sh release`), not by the card.
- The coverage map, `.conveyor/coverage.jsonl`, lists for each function of the engine's shell files, of
  `.claude/scripts/dashboard.sh` and of the hooks the test cases that ran it (engine cases, parts of
  `dashboard.test.sh`, `dashboard-cards.test.sh`, `dashboard-local.test.sh` and of the hooks' tests that `CONVEYOR_SHELL_TEST_CASE` selects in (each check of
  `bash-guardrails.test.sh`, `bash-guardrails-refusals.test.sh` and `bash-guardrails-writes.test.sh`), other test files whole). A change to functions alone that the map holds runs only those cases,
  in place of the area. A change outside any function, to a function the map does not hold or lists no case for, or to
  one changed since the map was traced, runs by the area, as above. `bash .conveyor/coverage.sh` traces every case
  once and writes the map; run it by hand and commit the map, never on a card's test step. The map check
  (`test-changed.sh --check`) says how old the map is.
- No whole test runs on main: the whole test on main is off for this project (its pack, `.conveyor/project.json`,
  names no `test.main`). Its `test.full` runs `.conveyor/test-full.sh`, so the Board's Run full test suite and Push
  landed buttons are enabled.
- Each area file under `conveyor/tests/` is a test file of its own. A card's Test step runs each area file it selects
  in its own process and test slot, with only its chosen cases, side by side with the other area files on the
  machine's test slots. The runner, `conveyor/conveyor.test.sh`, runs them, given that file's cases alone. The result
  names the area file: a failure, a main-red record, a flaky entry, a Tests page row and a CPU time read as
  `conveyor/tests/release.test.sh: relpass`. A failed case runs again by
  name in its own area file. A record made before this that names `conveyor/conveyor.test.sh: <case>` still reads:
  the case counts for the area file that defines it. `bash conveyor/tests/<area>.test.sh` runs one area file by hand.
  A change that selects every case runs no area file on the card: the runner is whole-only (`wholeOnly` in
  `.conveyor/project.json`), so only the full test suite runs those cases, each in its area file.
- `bash conveyor/conveyor.test.sh` runs the whole engine test by hand. A new engine case goes in its area's file under
  `conveyor/tests/` (no case file over 600 lines), and a new engine source file in one area of
  `.conveyor/engine-areas.json` that names its case files: `test-changed.sh --check` fails for a file under
  `conveyor/lib/` in an area whose tests are `"all"` with no `why`, and for a case file no area lists.
- A case uses no lock or folder that other cards share: cards test side by side on one machine, so a shared release
  lock or cards folder makes one card's case fail another's. Its engine calls name its own main under `$T/$CASE` and
  its own cards folder (`loop`, or `CONVEYOR_CARDS=$T/$CASE/cards`); `conveyor/tests/lib.sh` unsets the
  `CONVEYOR_CARDS` and `CONVEYOR_MAIN` the run starts with.
- `/units` (`hooks/units.tsx`): `claude plugin test .` and `claude plugin validate .` in the plugin's checkout, and
  `bash hooks/units-fetch.test.sh` for its fetch. A card's test step runs the mod's test files (`hooks/*.test.tsx`)
  through `claude plugin test`, with one `-- ok` or `-- FAIL` line a file.
- To run one card in the foreground, with no service, run `CONVEYOR_MAIN="$PWD" conveyor.sh run 1` in the project's
  checkout. `CONVEYOR_MAIN` names the project, as the engine's own checkout is the default.
- This project runs no GitHub Actions. At each release, every test and the privacy check run on the build machine,
  before the tag (`conveyor.sh release-prep` and `conveyor.sh release`, [Releases](docs/releases.md)). No push or
  pull request starts a test run.

Windows under WSL is not named as supported: no test runs on it.

## License

Contributions are licensed under Apache-2.0, the project's license (LICENSE).
