# Releases

Each release has a version `X.Y.Z` and a tag `vX.Y.Z`.

- A release that only fixes things raises the last number (1.0.0 to 1.0.1).
- A release that adds a feature raises the middle number (1.0.1 to 1.1.0).
- A release with a change that breaks an existing project's settings (`.conveyor/project.json`) or setup raises the
  first number (1.1.0 to 2.0.0).

[Setup](setup.md#following-releases-or-main-or-pinning-a-commit) says how a project follows releases.

## Making a release

Only the repository owner makes a release:

1. Read the Claude pricing page and the OpenAI pricing page again. Update the Board's built-in model prices (`PRICES`
   and `LONG_PRICES` in `.claude/scripts/dashboard_limit.py`) to match them, with the date you read them in the
   comment above the table. Commit the change on `main`.
2. On the build machine, run `conveyor.sh release-prep <version>`. It writes a draft of the release notes from the
   commits since the last tag, and prints the path of the draft. The head of `main` on GitHub has no notes yet, so it
   stops there.
3. Edit the draft into the release notes: sections for users, plain bullets, and no file, issue or commit names. Commit
   it as `docs/releases/<version>.md` on `main`, and push it.
4. Run `conveyor.sh release-prep <version>` again. It runs the whole test suite (`test.full` in the pack, the project's settings, `.conveyor/project.json`) on the head of
   `main` on GitHub, and posts the result on that commit as the commit status `conveyor/release-suite`. Push nothing to
   `main` after this step and before the next.
5. On GitHub, open Actions, then Release, then Run workflow on `main`, and type the version. The workflow first runs
   CI (every test and the privacy check, on Ubuntu and macOS) on the commit to release. CI runs only at a release,
   never on a push or a pull request. When a CI job fails, the release stops before the tag, and the run names the
   failed step. Then the workflow stops, and changes nothing, when one of these is true:
   - the person who runs it is not the owner,
   - the version is not higher than the newest tag, or its tag exists,
   - the newest `conveyor/release-suite` status on the commit is not a pass,
   - the privacy check finds something in a commit since the last tag,
   - there is no notes file.

   The log gives the reason.
6. When all checks pass, the workflow sets the version in `plugin.json` and the tag in the marketplace entry, and
   makes the annotated tag. Then it pins the marketplace entry to the commit of that tag, and makes the GitHub release
   with the notes as its text.
