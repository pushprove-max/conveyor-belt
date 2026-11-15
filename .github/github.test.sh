#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 30
# The repository's GitHub files, as GitHub reads them. YAML is parsed with Perl's core CPAN::Meta::YAML, on macOS and
# Linux alike, so the test needs nothing installed.
# Bugs it catches: a GitHub Actions workflow or a Dependabot version-updates file in the repository (each starts runs
# that cost the owner's Actions minutes, and the account can no longer start Actions jobs: the project runs none, and a
# release is `conveyor.sh release` on the build machine); a CODEOWNERS file that does not give everything to the
# owner; a pull request template without its parts or the sign-off reminder; a README with a CI badge; an issue
# chooser that does not send questions to Discussions.
set -uo pipefail
SRC=$(cd "$(dirname "$0")/.." && pwd -P)
fail() { echo "FAIL [github]: $*" >&2; exit 1; }

# No workflow and no Dependabot version updates: GitHub runs any file under .github/workflows/, and Dependabot's
# updates of a dependabot.yml.
w=$(find "$SRC/.github/workflows" -type f 2>/dev/null | sed "s|^$SRC/||")
[ -z "$w" ] || fail "a GitHub Actions workflow is in the repository: $w"
for f in dependabot.yml dependabot.yaml; do [ ! -e "$SRC/.github/$f" ] || fail "Dependabot version updates are on: .github/$f"; done

# The issue chooser, parsed. One line per check it fails; nothing when it passes.
out=$(perl -MCPAN::Meta::YAML -e '
  my $d = shift; my @bad;
  my $y = eval { CPAN::Meta::YAML->read("$d/ISSUE_TEMPLATE/config.yml") }; my $cfg = $y && $y->[0];
  ref $cfg eq "HASH" or do { push @bad, "config.yml is not a YAML mapping: " . ($@ || CPAN::Meta::YAML->errstr || "empty"); $cfg = {} };
  grep { ($_->{url} // "") =~ m{/discussions$} } @{ $cfg->{contact_links} || [] }
    or push @bad, "config.yml does not send questions to Discussions";
  print map { "$_\n" } @bad;
' "$SRC/.github" 2>&1) || fail "perl could not run the check: $out"
[ -z "$out" ] || fail "$out"

# CODEOWNERS: each line a pattern and its owners; everything is the owner's.
C=$SRC/.github/CODEOWNERS
[ -f "$C" ] || fail "there is no .github/CODEOWNERS"
bad=$(grep -vE '^[[:space:]]*(#|$)' "$C" | grep -vE '^[^[:space:]]+([[:space:]]+@[A-Za-z0-9-]+(/[A-Za-z0-9_.-]+)?)+[[:space:]]*$')
[ -z "$bad" ] || fail "CODEOWNERS has a line that is not a pattern and its owners: $bad"
grep -qE '^\*[[:space:]]+@pushprove-max[[:space:]]*$' "$C" || fail "CODEOWNERS does not give every file to @pushprove-max"

# The pull request template: what and why, the issue, the testing, the sign-off.
P=$SRC/.github/pull_request_template.md
for s in '## What changes and why' 'Closes #' '## How it was tested' '## Sign-off' 'git commit -s'; do
  grep -qF -- "$s" "$P" 2>/dev/null || fail "the pull request template has no \"$s\""
done

# No CI badge: no CI runs, so a badge would show a stale or missing run.
! grep -qE 'actions/workflows/|alt="CI"' "$SRC/README.md" || fail "the README shows a CI badge"
echo "ok [github]: no workflow and no Dependabot updates; CODEOWNERS, the template and the issue chooser are in place"
