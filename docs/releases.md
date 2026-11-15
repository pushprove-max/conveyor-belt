# Releases

Each release has a version `X.Y.Z` and a tag `vX.Y.Z`.

- A release that only fixes things raises the last number (1.0.0 to 1.0.1).
- A release that adds a feature raises the middle number (1.0.1 to 1.1.0).
- A release with a change that breaks an existing project's settings (`.conveyor/project.json`) or setup raises the
  first number (1.1.0 to 2.0.0).

[Setup](setup.md#following-releases-or-main-or-pinning-a-commit) says how a project follows releases.

## Making a release

Only the repository owner decides a release. The Foreman runs `conveyor.sh release` only after the owner says yes
in chat. The project runs no GitHub Actions: every step runs on the build machine.

1. Read the Claude pricing page and the OpenAI pricing page again. Update the Board's built-in model prices (`PRICES`
   and `LONG_PRICES` in `.claude/scripts/dashboard_limit.py`) to match them, with the date you read them in the
   comment above the table. Commit the change on `main`.
2. On the build machine, run `conveyor.sh release-prep <version>`. A model writes a draft of the release notes in
   the [release notes style](#release-notes). It reads the issues that landed since the last tag, their
   titles and text, and the commit subjects. The command prints the path of the draft, and says if the draft breaks
   a rule of the style. The head of `main` on GitHub has no notes yet, so it stops there.
3. Read the draft and change what you need. Commit it as `docs/releases/<version>.md` on `main`, and push it.
4. You can run `conveyor.sh release-prep <version>` again. It runs the whole test suite (`test.full` in the pack, the
   project's settings, `.conveyor/project.json`) on the head of `main` on GitHub, and posts the result on that commit
   as the commit status `conveyor/release-suite`. It does not run the suite when the notes break the style. Push
   nothing to `main` after this step and before the next.
5. Ask the owner for a yes in chat. After the yes, run `conveyor.sh release <version>` in the main checkout, on `main`.
   It stops, and changes nothing, when one of these is true:
   - the version is not higher than the newest tag, or its tag exists,
   - the checkout is not at the head of `main` on GitHub, or it has changes that are not committed,
   - there is no notes file, or the notes break a rule of the style that the style check reads,
   - the privacy check finds something in the tracked files or in a commit since the last tag,
   - the whole test suite does not pass on the commit. When the newest `conveyor/release-suite` status on the commit
     is a pass (step 4), the suite does not run again. Otherwise the command runs it.

   The output gives the reason.
6. When all checks pass, the command sets the version in `plugin.json` and the tag in the marketplace entry, and
   makes the annotated tag. Then it pins the marketplace entry to the commit of that tag, pushes `main` and the tag,
   and makes the GitHub release with the notes as its text (`gh release create`).

## A release from the Board

The Release panel on the Board's Overview tab does steps 4 to 6 ([The Board](board.md#release)). Type the version and
click **Release** two times. The second click is the owner's yes. Conveyor runs `conveyor.sh release-run <version>`:
`release-prep`, then `release` when the suite passes. The output of the two is in `release/run.log` in the cards
folder. When a step stops, the panel shows each reason, and nothing more runs. `/units` shows the run while it is in
progress ([/units](units.md)). `conveyor.sh release-run stop` is the panel's **Stop**.

## Release notes

The release notes are for the people who use Conveyor. Each release has its notes in `docs/releases/<version>.md`,
and the GitHub release shows them.

- The first line is the heading `# <version>`. The next line says in one sentence what the release is about.
- `##` sections have the name of what a user does or sees, for example Cards, The Board, In Claude Code or Setup.
  There are no `###` headings.
- Each bullet tells one change in plain English: what the user sees or can do now.
- The notes name no file, script or function, no path, no issue or pull request number, no commit hash and no
  internal part of the engine, and have no "Closes" line. They can name what a person types or sees: a slash command,
  a setup question, a setting or a button.
- Changes that only touch tests, refactors or tools are not in the notes, or are in one plain line when a user sees
  no change.

`conveyor.sh release` and `conveyor.sh release-prep` check the notes for a `###` heading, an issue number, a commit
hash, a path or file name, and "Closes". When they find one, they stop and give the line and the rule.
