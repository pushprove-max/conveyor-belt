# Conveyor Belt

This repository is the Conveyor Belt plugin for Claude Code. It turns GitHub issues into cards that a loop builds,
reviews, tests and lands. The belt builds itself: most changes here arrive as cards. `README.md` says what a user
sees; `conveyor/README.md` is the engine reference; the pages under `docs/` cover each part. Read those for how a
part works. This file holds only what the code does not tell you.

`AGENTS.md` is a link to this file, so the Codex reviewer and the other reviewers read the same text.

## Layout

- `conveyor/`: the engine. `conveyor/conveyor.sh` is its entry point and command table, `conveyor/lib/` its parts,
  `conveyor/tests/` its test cases (run by `conveyor/conveyor.test.sh`), `conveyor/rules/` the rules a card session
  and a review are given, `conveyor/foreman/` and `conveyor/lanes/` the Foreman and the lanes.
- `.claude/dashboard/` (the page) and `.claude/scripts/` (its server and `dashboard.sh`): the Board. Its tests are
  under `.claude/scripts/__tests__/`.
- `commands/`: the plugin's slash commands. `hooks/`: the plugin's hooks (`hooks/hooks.json`) and its mod (the
  `/units` views and the auto band, `hooks/index.tsx`). `.claude/hooks/`: the guard hooks those hooks and a card
  session run (`conveyor/card-settings.json` names a card's). `shim.sh`: runs a plugin hook or command from the
  project's engine install, not from the plugin's own copy.
- `.conveyor/`: this project's pack. `.conveyor/project.json` holds the test commands and the owner-approved files,
  `.conveyor/engine-areas.json` maps each engine file to its case files, `.conveyor/card-rules.md` adds this
  project's rules to every card.

## Rules

The rules are in `CONTRIBUTING.md` (Rules and Tests). A card session also gets `conveyor/rules/card-core.md` and
`.conveyor/card-rules.md`; it does not load this file. A change to a rule every card must keep goes in one of those
two files, not here.

These points cost the most when missed:

- The repository is public. A name, a non-noreply email, a home path or a private host in any file fails the privacy
  check (`conveyor/privacy/check.sh`). Fixtures use example.com, `$HOME`-relative paths and 192.0.2.x.
- The plugin runs in other people's projects. No host project's names, paths or labels in code.
- The owner approves every change to how the engine builds, reviews, fixes, tests, lands or pushes (the pack's
  `pipelineFiles`). Change those files only where the issue asks for it.
- The engine is bash 5.1 and jq and runs on macOS and Linux. A reading of the host that differs by system (`date -d`,
  `stat -c`, files under /proc) goes through a helper in `conveyor/lib/portable.sh`. The Board is the Python 3 standard library.
- Each source file starts with the SPDX header; `spdx.test.sh` names a file without one.
- A change to what a user sees changes its page in `docs/` or `README.md` in the same change. Those pages, the
  Board's texts and the engine's reason texts follow `conveyor/rules/ste80.md`; `README-pages.test.sh` and
  `README.test.sh` check them. On those pages the product is Conveyor, not Conveyor Belt (the plugin's name).

## Tests

- Tests run on the build machine, by the loop or by hand there. A session on the owner's Mac does not run them.
- Run only the tests your change touches: `bash conveyor/conveyor.test.sh <case>` for engine cases, a Board test by
  its own file. `bash .conveyor/test-changed.sh` picks them for a change. Never run the whole engine test in a session:
  a card's Test step runs what the change touches, and a release runs every test.
- `node --test` needs `--max-old-space-size=4096`, or use `npm run test:files`.
- A new engine case goes in its area's file under `conveyor/tests/` (600 lines at most per file), never in
  `conveyor/conveyor.test.sh`. A new engine file gets one line in `.conveyor/engine-areas.json`, or the map check
  fails.
- Each area file is a test file of its own. A card's Test step runs each area file it selects in its own process
  and test slot, with only its chosen cases (the runner given that file's cases), side by side with the others. Its
  result, failures, flaky entries and CPU time name the area file: the case relpass is
  reported under `conveyor/tests/release.test.sh`.
  `bash` on one area file (as `bash conveyor/tests/release.test.sh`) runs it by hand. `conveyor/conveyor.test.sh` runs every case: the
  whole engine test.
- A test file stays under the CPU budget (`conveyor/README.md`, The CPU budget of a test file). Why and how:
  `conveyor/tests/speed/README.md`.
- No test starts a browser; Board tests use jsdom (`.conveyor/no-browser-tests.sh` fails a run that adds one).
