# Conveyor Belt project rules

- This repository will be public. Never write a person's name, an email that is not a GitHub noreply address, a home
  path, a private host name or address, a private issue number from another repository, or a ruling id into code,
  comments, tests, fixtures, docs or commit messages. Test fixtures use example.com addresses, $HOME-relative paths and 192.0.2.x (TEST-NET) addresses.
- The plugin is generic: no host-project names (a host project's name, its env names, paths or labels) outside docs that name a
  project only as an example.
- bash 5.1 + jq for the engine, Python 3 standard library for the Board unless a card names a pinned library; macOS and
  Linux both supported (lib/portable.sh).
- The smallest change that fully solves the issue; no feature flags; no compatibility code for old data.
- A test encodes why the behaviour matters and fails if the behaviour breaks; never weaken an existing test to pass.
- A new engine test case goes in the area file it belongs to under `conveyor/tests/`, or a new file there; never in
  the runner, `conveyor/conveyor.test.sh`. No case file over 600 lines.
- A build or fix that changes a lock, a retry, a snapshot or a merge decision names what must stay true and the other
  reader or writer, and its test forces that one to act at the weak point through the real caller: for example, pause
  the idle merge after its last rule read, change the rule, resume, and assert no merge was asked. The test asserts the
  stored state or the outside action, never after a sleep, and never by forcing the order inside a helper: the real
  command can stay racy while such a test passes.
- No wrapper that only runs other tests again: the test run already runs them, so it proves nothing and doubles their
  time (#357 removed two, 31 s of every run cut).
- A case that runs several fixtures one after another is split into one case per fixture: the runner runs cases side
  by side, so the file takes about its slowest fixture (`metrics` 79% cut, `stall` 71%).
- A case that proves one engine function calls that function; a whole card run is kept for what only a whole card
  proves: a card run pays for the loop, its sessions and waits (`testfails` 76% cut, #362; `testrec` 89%, #371).
- These three rules, with their measurements, are also in `conveyor/tests/speed/README.md`.
- A card changes the suite's runner `.conveyor/test-full.sh`, the engine's runner `conveyor/conveyor.test.sh` or the
  pack's `test` settings only when its issue names that file or setting: such a change makes the next release run
  every test file, not only the files that changed or failed (`conveyor/commands/release-prep.sh`). When the card must
  make one, its reply says why no other place works. The reviewer reports a change to one of them that the issue does
  not name as a P2 finding.
- A new engine source file goes in exactly one area of `.conveyor/engine-areas.json` (each engine source file to its
  case files), or the test run fails. The map is one fact a line (`{"area": "<area>", "file": "<path>"}`, or `"test":
  "<case file>"`): add a line, never a list.
- Board texts, engine reason texts, `README.md`, `conveyor/README.md` and the pages under `docs/` follow
  `conveyor/rules/ste80.md` (the pinned STE80 Humanizer, both passes, no AI tells), in place of the ASD-STE100 rules.
  Keep the form a line must have, and the names of files, commands and settings. The pages say what a user can see or
  do: no account of how a file is made, how this repository's own tests work, or history. A setting is named as a
  setting, with where it is set, never as a fixed number. `README-pages.test.sh` checks the tells it can read.
- No browser tests, by the owner's order of 2026-11-14: no test starts a real or headless browser (Chromium, Chrome,
  playwright, puppeteer), and no Done-when asks for one. The Board's layout is not tested; its tests use jsdom.
  `.conveyor/no-browser-tests.sh` fails any test run that adds one.

Your own test runs, in a build or fix session:
- In a build or fix session, run the cases you added or changed and the existing cases that cover the code you changed.
  Chosen engine cases: `timeout 240 bash conveyor/conveyor.test.sh <case> [<case> ...]` (the case is the name after
  `t_`); a Board test by its own file under `.claude/scripts/__tests__/` (`bash`, `node --test` or `python3` on it).
- Run `.conveyor/test-changed.sh` at most once in a session, and only when the change touches code shared across areas
  of the engine. Do not run the whole `conveyor/conveyor.test.sh`: the Test step
  runs what the change touches before the card lands.
