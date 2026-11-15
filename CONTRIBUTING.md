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
- The engine is bash 5.1 and jq; the Board is Python 3's standard library unless an issue names a pinned library.
  Both run on macOS and Linux (`conveyor/lib/portable.sh`).
- The plugin is generic: no project's own names, paths or labels outside docs that name one as an example.
- This repository is public. No person's name, no email that is not a GitHub noreply address, no home path, no
  private host name or address goes into code, comments, tests, fixtures, docs or commit messages. Fixtures use
  example.com addresses, `$HOME`-relative paths and 192.0.2.x addresses. The privacy check finds most of these:
  `git ls-files -z | xargs -0 bash conveyor/privacy/check.sh`.

## Tests

A test says why the behaviour matters and fails when it breaks; an existing test is never weakened to pass.

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
  `dashboard.test.sh` and of the hooks' tests that `CONVEYOR_SHELL_TEST_CASE` selects in (each check of
  `bash-guardrails.test.sh`), other test files whole). A change to functions alone that the map holds runs only those cases,
  in place of the area. A change outside any function, to a function the map does not hold or lists no case for, or to
  one changed since the map was traced, runs by the area, as above. `bash .conveyor/coverage.sh` traces every case
  once and writes the map; run it by hand and commit the map, never on a card's test step. The map check
  (`test-changed.sh --check`) says how old the map is.
- No whole test runs on main: the whole test on main is off for this project (its pack, `.conveyor/project.json`,
  names no `test.main`), and its pack names no `test.full`, so the Board shows its Run full test suite and Push landed
  buttons disabled.
- `bash conveyor/conveyor.test.sh` runs the whole engine test by hand. A new engine case goes in its area's file under
  `conveyor/tests/` (no case file over 600 lines), and a new engine source file in one area of
  `.conveyor/engine-areas.json` that names its case files: `test-changed.sh --check` fails for a file under
  `conveyor/lib/` in an area whose tests are `"all"` with no `why`, and for a case file no area lists.
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
