#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 30
# The security policy and the issue forms, as GitHub reads them. Each file under .github/ISSUE_TEMPLATE/ is parsed as
# YAML (Perl's core CPAN::Meta::YAML, on macOS and Linux alike, so the test needs nothing installed).
# Bugs: a form GitHub cannot parse, so the new-issue page drops it; a bug report with no Conveyor or Claude Code
# version, so it cannot be reproduced; a security report sent to a public issue, as config.yml does not point to
# SECURITY.md or SECURITY.md does not name the private report.
set -uo pipefail
SRC=$(cd "$(dirname "$0")" && pwd -P)
fail() { echo "FAIL [security]: $*" >&2; exit 1; }
D=$SRC/.github/ISSUE_TEMPLATE
[ -f "$D/bug.yml" ] && [ -f "$D/feature.yml" ] && [ -f "$D/config.yml" ] || fail "the bug form, the feature form or config.yml is missing"
grep -qF 'private vulnerability reporting' "$SRC/SECURITY.md" || fail "SECURITY.md does not name GitHub's private vulnerability reporting"

# One line per check the files fail; nothing when they pass.
out=$(perl -MCPAN::Meta::YAML -e '
  my $d = shift; my @bad;
  sub req { my ($f, $id) = @_; my ($e) = grep { ($_->{id} // "") eq $id } @{ $f->{body} || [] };
    $e && ($e->{validations}{required} // "") eq "true" }
  for my $p (glob "$d/*") {
    my $y = eval { CPAN::Meta::YAML->read($p) }; my $doc = $y && $y->[0];
    (my $n = $p) =~ s{.*/}{};
    if (ref $doc ne "HASH") { push @bad, "$n is not a YAML mapping: " . ($@ || CPAN::Meta::YAML->errstr || "empty"); next }
    if ($n eq "config.yml") {
      grep { ($_->{url} // "") =~ m{/SECURITY\.md$} } @{ $doc->{contact_links} || [] }
        or push @bad, "config.yml does not link SECURITY.md";
      next;
    }
    $doc->{name} && $doc->{description} && ref $doc->{body} eq "ARRAY" && @{ $doc->{body} }
      or push @bad, "$n has no name, description or body";
  }
  my $bug = eval { CPAN::Meta::YAML->read("$d/bug.yml")->[0] } || {};
  for my $id (qw(conveyor-version claude-code-version)) {
    req($bug, $id) or push @bad, "bug.yml does not ask for $id as a required field";
  }
  print map { "$_\n" } @bad;
' "$D" 2>&1) || fail "perl could not run the check: $out"
[ -z "$out" ] || fail "$out"
echo "ok [security]: the forms parse, the bug form requires both versions, config.yml links SECURITY.md"
