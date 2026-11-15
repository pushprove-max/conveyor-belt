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
2. On the build machine, run `conveyor.sh release-prep <version>`. It writes a draft of the release notes from the
   commits since the last tag, and prints the path of the draft. The head of `main` on GitHub has no notes yet, so it
   stops there.
3. Edit the draft into the release notes: sections for users, plain bullets, and no file, issue or commit names. Commit
   it as `docs/releases/<version>.md` on `main`, and push it.
4. You can run `conveyor.sh release-prep <version>` again. It runs the whole test suite (`test.full` in the pack, the
   project's settings, `.conveyor/project.json`) on the head of `main` on GitHub, and posts the result on that commit
   as the commit status `conveyor/release-suite`. Push nothing to `main` after this step and before the next.
5. Ask the owner for a yes in chat. After the yes, run `conveyor.sh release <version>` in the main checkout, on `main`.
   It stops, and changes nothing, when one of these is true:
   - the version is not higher than the newest tag, or its tag exists,
   - the checkout is not at the head of `main` on GitHub, or it has changes that are not committed,
   - there is no notes file,
   - the privacy check finds something in the tracked files or in a commit since the last tag,
   - the whole test suite does not pass on the commit. When the newest `conveyor/release-suite` status on the commit
     is a pass (step 4), the suite does not run again. Otherwise the command runs it.

   The output gives the reason.
6. When all checks pass, the command sets the version in `plugin.json` and the tag in the marketplace entry, and
   makes the annotated tag. Then it pins the marketplace entry to the commit of that tag, pushes `main` and the tag,
   and makes the GitHub release with the notes as its text (`gh release create`).
