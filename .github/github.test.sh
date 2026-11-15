#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 30
# The repository's GitHub files, as GitHub reads them. YAML is parsed with Perl's core CPAN::Meta::YAML, on macOS and
# Linux alike, so the test needs nothing installed.
# Bugs it catches: a workflow step that uses an Action by a tag or a branch, which its owner can move to other code,
# in place of a full commit id (with the tag in a comment, for Dependabot); a Dependabot, Scorecard or DCO file GitHub
# cannot parse, or one that leaves out a package set, its schedule or the pull request it checks; a Dependabot
# file that lets TypeScript 7 in, or that holds back any other npm update; a CODEOWNERS file
# that does not give everything to the owner; a pull request template without its parts or the sign-off reminder; a
# README without the Scorecard badge, or with a CI badge; a CI workflow that runs on a push or a pull request, or a
# release that tags without needing its CI job; an issue chooser that does not send questions to Discussions; actions/checkout
# or actions/setup-node left on a major before 7.
set -uo pipefail
SRC=$(cd "$(dirname "$0")/.." && pwd -P)
fail() { echo "FAIL [github]: $*" >&2; exit 1; }

# unpinned <workflow>...: each `uses:` of the files that names an Action by anything but a full commit id followed by
# its tag in a comment, as `<file>:<line>: <value>`. A local action (./path) needs no pin.
unpinned() {
  awk '
    /^[ \t]*(-[ \t]+)?uses:/ {
      v = $0; sub(/^[ \t]*(-[ \t]+)?uses:[ \t]*/, "", v); u = v; sub(/[ \t]+#.*$/, "", u); gsub(/["\047]/, "", u)
      if (u ~ /^\.\//) next
      id = u; sub(/^[^@]*@/, "", id)
      if (u !~ /^[A-Za-z0-9._-]+\/[A-Za-z0-9._\/-]+@[0-9a-f]+$/ || length(id) != 40 || v !~ /[ \t]#[ \t]*v[0-9]/) print FILENAME ":" FNR ": " v
    }' "$@"
}

W=("$SRC"/.github/workflows/*.yml)
[ "${#W[@]}" -ge 4 ] || fail "the workflows are missing: ${W[*]}"
out=$(unpinned "${W[@]}") || fail "the workflows could not be read: $out"
[ -z "$out" ] || fail "an Action is not pinned to a full commit id with its tag in a comment: $out"
grep -qE '^[ \t]*(-[ \t]+)?uses:' "${W[@]}" || fail "no workflow has a uses: line, so the pin check read nothing"
# checkout and setup-node are at major 7 (Dependabot's update, applied by a card): a step left on an older major, or
# a pin put back to one, fails here. Each line is pinned by the check above.
for a in actions/checkout actions/setup-node; do
  grep -qE "uses:[ \t]*[\"']?$a@" "${W[@]}" || fail "no workflow uses $a"
  old=$(grep -nE "uses:[ \t]*[\"']?$a@" "${W[@]}" | grep -vE "@[0-9a-f]{40}[\"']?[ \t]+#[ \t]*v7\.")
  [ -z "$old" ] || fail "$a is not at major 7, pinned by commit with its tag: $old"
done

# A fixture workflow: a tag, a short commit id, a pin with no tag comment, and a pinned step with its tag.
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
printf '%s\n' 'jobs:' '  a:' '    steps:' '      - uses: actions/checkout@v4' \
  '      - uses: actions/setup-node@49933ea # v4.4.0' \
  "      - uses: \"actions/cache@$(printf '%040d' 0)\"" \
  "      - uses: actions/checkout@$(printf 'a%.0s' {1..40}) # v4.4.0" '      - uses: ./local-action' > "$T/w.yml"
out=$(unpinned "$T/w.yml" | sed "s|^$T/||" | tr '\n' '|')
[ "$out" = 'w.yml:4: actions/checkout@v4|w.yml:5: actions/setup-node@49933ea # v4.4.0|w.yml:6: "actions/cache@0000000000000000000000000000000000000000"|' ] \
  || fail "the pin check named [$out], not the tag, the short id and the pin with no tag comment"

# The files GitHub reads, parsed. One line per check they fail; nothing when they pass.
out=$(perl -MCPAN::Meta::YAML -e '
  my $d = shift; my @bad;
  sub doc { my $y = eval { CPAN::Meta::YAML->read("$d/$_[0]") }; my $x = $y && $y->[0];
    ref $x eq "HASH" ? $x : do { push @bad, "$_[0] is not a YAML mapping: " . ($@ || CPAN::Meta::YAML->errstr || "empty"); {} } }
  my $dep = doc("dependabot.yml");
  ($dep->{version} // "") eq "2" or push @bad, "dependabot.yml is not version 2";
  my %up = map { (($_->{"package-ecosystem"} // "") . " " . ($_->{directory} // "")) => ($_->{schedule}{interval} // "") }
    @{ $dep->{updates} || [] };
  for my $k ("github-actions /", "npm /", "npm /docs/demo", "pip /.claude/scripts") {
    ($up{$k} // "") eq "weekly" or push @bad, "dependabot.yml has no weekly update for $k";
  }
  # The root npm set skips TypeScript majors (7 has no classic API for new-test-file-guard.sh) and nothing else, so
  # every other package, and TypeScript minors and patches, still get updates.
  my ($npm) = grep { ($_->{"package-ecosystem"} // "") eq "npm" && ($_->{directory} // "") eq "/" } @{ $dep->{updates} || [] };
  my @ig = @{ ($npm || {})->{ignore} || [] };
  my @ts = grep { ($_->{"dependency-name"} // "") eq "typescript" } @ig;
  (@ts == 1 && join(",", @{ $ts[0]{"update-types"} || [] }) eq "version-update:semver-major")
    or push @bad, "dependabot.yml npm / does not ignore semver-major updates of typescript alone";
  @ig == @ts or push @bad, "dependabot.yml npm / ignores a package other than typescript";
  ($npm || {})->{"allow"} and push @bad, "dependabot.yml npm / has an allow list, so it may skip other packages";
  my $sc = doc("workflows/scorecard.yml");
  @{ $sc->{on}{schedule} || [] } or push @bad, "scorecard.yml has no schedule";
  grep { $_ eq "main" } @{ $sc->{on}{push}{branches} || [] } or push @bad, "scorecard.yml does not run on a push to main";
  my @st = map { $_->{uses} // "" } @{ $sc->{jobs}{analysis}{steps} || [] };
  grep { m{^ossf/scorecard-action@} } @st or push @bad, "scorecard.yml does not run ossf/scorecard-action";
  grep { m{^github/codeql-action/upload-sarif@} } @st or push @bad, "scorecard.yml does not send its results to code scanning";
  my $dco = doc("workflows/dco.yml");
  ($dco->{on} // "") eq "pull_request" or push @bad, "dco.yml does not run on pull_request alone";
  grep { ($_->{run} // "") =~ m{\.github/dco/dco\.sh} } @{ $dco->{jobs}{dco}{steps} || [] } or push @bad, "dco.yml does not run dco.sh";
  # CI runs only at a release (#651): a push or pull request trigger spent Actions minutes on every push.
  my $ci = doc("workflows/ci.yml"); my $on = $ci->{on};
  ref $on eq "HASH" or push @bad, "ci.yml has no mapping of triggers: " . (ref $on ? ref $on : $on // "none");
  $on = {} unless ref $on eq "HASH";
  exists $on->{$_} and push @bad, "ci.yml runs on $_" for qw(push pull_request);
  exists $on->{$_} or push @bad, "ci.yml has no $_ trigger" for qw(workflow_call workflow_dispatch);
  ($ci->{concurrency}{"cancel-in-progress"} // "") eq "true" or push @bad, "ci.yml does not cancel a run still going when it starts again";
  # The release calls CI and tags only after it: the release job needs the job that uses ci.yml.
  my $rel = doc("workflows/release.yml"); my $rj = $rel->{jobs} || {};
  my @cij = grep { ($rj->{$_}{uses} // "") eq "./.github/workflows/ci.yml" } keys %$rj;
  @cij or push @bad, "release.yml has no job that uses ./.github/workflows/ci.yml";
  my @tag = grep { ($_->{run} // "") =~ m{\.github/release/release\.sh} } @{ ($rj->{release} || {})->{steps} || [] };
  @tag or push @bad, "release.yml has no release job that runs release.sh";
  my $nd = ($rj->{release} || {})->{needs} // [];
  my %nd = map { $_ => 1 } (ref $nd ? @$nd : $nd);
  !@cij || grep({ $nd{$_} } @cij) or push @bad, "release.yml tags without needing the CI job (needs: " . join(",", keys %nd) . ")";
  my $cfg = doc("ISSUE_TEMPLATE/config.yml");
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

# The README's badge row shows the Scorecard badge.
grep -qF 'src="https://api.scorecard.dev/projects/github.com/pushprove-max/conveyor-belt/badge"' "$SRC/README.md" \
  || fail "the README does not show the OpenSSF Scorecard badge"
# No CI badge (#651): CI runs only at a release, so the badge would show the last release's run, read as main's state.
! grep -qE 'actions/workflows/ci\.yml|alt="CI"' "$SRC/README.md" || fail "the README shows a CI badge"
echo "ok [github]: every Action is pinned by commit; Dependabot, Scorecard, DCO, CODEOWNERS, the template and the badge are in place"
