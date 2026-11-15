#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 60
# The release workflow's script (release.sh, beside this file) against fixture repos: a work clone at the commit to
# release, its origin a bare repo, gh a stub (the commit statuses it is given; the release it is asked to make).
# Bugs: a release is cut by someone other than the owner, at a version not above the last, on a commit with no passing
# whole-suite status, with a private text in a commit since the last release (a later commit removing it included), or
# with no notes; a refusal that does not say why, or that still tags, pushes or releases. And, all checks passing:
# plugin.json's version, the marketplace's ref and sha, the tag or the release body are not the new release's.
set -uo pipefail
SRC=$(cd "$(dirname "$0")/../.." && pwd -P)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fail() { echo "FAIL [release]: $*" >&2; exit 1; }
AT=@ # an address is put together, so this file holds none itself (the privacy check runs over it)
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t${AT}example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t${AT}example.com GIT_CONFIG_GLOBAL=/dev/null
export GITHUB_REPOSITORY=o/p RELEASE_OWNER=o RELEASE_REF=refs/heads/main

# The fixture, made once: v1.0.0 released (a private text before it, which is no longer the check's), then a commit
# adding the 1.1.0 notes. Each case copies it (case <name>) and runs in its own copy.
F=$T/fixture; W=$F/work
mkdir -p "$W/.claude-plugin" "$W/conveyor/privacy" "$W/docs/releases" "$F/stub" && cp "$SRC/conveyor/privacy/check.sh" "$W/conveyor/privacy/" || fail "no fixture"
git init -q -b main "$W" && git init -q --bare -b main "$F/origin" && git -C "$W" remote add origin "$F/origin"
jq -n '{name: "p", version: "1.0.0"}' > "$W/.claude-plugin/plugin.json"
jq -n --arg s "$(printf 'a%.0s' {1..40})" '{name: "m", plugins: [{name: "p", source: {source: "github", repo: "o/p", ref: "v1.0.0", sha: $s}}, {name: "q", source: {source: "github", repo: "o/q", ref: "v9.0.0"}}]}' > "$W/.claude-plugin/marketplace.json"
echo "old${AT}example.com" > "$W/old.txt"
git -C "$W" add -A && git -C "$W" commit -qm 'the first release' && git -C "$W" tag -a v1.0.0 -m 'Release 1.0.0' || fail "no fixture"
printf '# 1.1.0\n\n## Fixes\n\n- A fix\n' > "$W/docs/releases/1.1.0.md"
git -C "$W" add -A && git -C "$W" commit -qm 'fix: notes' && git -C "$W" push -q origin main v1.0.0 || fail "no fixture"
# gh: `api` prints $STUB/statuses (newest first, as GitHub lists them); `release` notes its arguments and keeps the
# notes file it was given as the body.
cat > "$F/stub/gh" <<'EOF'
#!/usr/bin/env bash
case $1 in
  api) cat "$STUB/statuses" ;;
  release) printf '%s\n' "$*" >> "$STUB/released"; while [ $# -gt 0 ]; do [ "$1" != --notes-file ] || cp "$2" "$STUB/body"; shift; done ;;
esac
EOF
chmod +x "$F/stub/gh"
echo '[{"context":"other","state":"failure"},{"context":"conveyor/release-suite","state":"success"},{"context":"conveyor/release-suite","state":"failure"}]' > "$F/stub/statuses"

# case <name>: the case's copy of the fixture, in C (W: its work clone, STUB: its stubs).
case_() { C=$T/$1; cp -a "$F" "$C"; W=$C/work STUB=$C/stub; git -C "$W" remote set-url origin "$C/origin"; }
rel() { # <version> [VAR=value...]: runs release.sh in the case's clone at its HEAD; its output in $C/out
  local v=$1; shift
  (cd "$W" && env PATH="$STUB:$PATH" STUB="$STUB" RELEASE_ACTOR=o RELEASE_TRIGGER=o RELEASE_SHA="$(git rev-parse HEAD)" "$@" bash "$SRC/.github/release/release.sh" "$v") > "$C/out" 2>&1
}
refused() { # <case> <version> <reason (grep -E)> [VAR=value...]
  local n=$1 v=$2 why=$3 o; shift 3
  o=$(git -C "$C/origin" rev-parse main)
  rel "$v" "$@"; [ $? = 1 ] || fail "$n: not refused: $(cat "$C/out")"
  grep -qE "refused, nothing tagged or released: .*$why" "$C/out" || fail "$n: the refusal does not say why ($why): $(cat "$C/out")"
  [ -z "$(git -C "$W" tag -l "v$v")" ] || [ "$v" = 1.0.0 ] || fail "$n: a refused release made the tag v$v"
  [ "$(git -C "$C/origin" tag -l)" = v1.0.0 ] && [ "$(git -C "$C/origin" rev-parse main)" = "$o" ] && [ ! -e "$STUB/released" ] \
    || fail "$n: a refused release pushed or released something: $(git -C "$C/origin" tag -l) $(cat "$STUB/released" 2>&1)"
}

case_ actor; refused actor 1.1.0 'only the repository owner \(o\).*someone' RELEASE_ACTOR=someone RELEASE_TRIGGER=someone
# A re-run started by someone else keeps github.actor as the first run's: the one who started this run counts too.
case_ rerun; refused rerun 1.1.0 'only the repository owner \(o\).*someone' RELEASE_TRIGGER=someone
case_ lower; refused lower 0.9.0 'the version 0.9.0 is not higher than the newest release, v1.0.0'
case_ exists; refused exists 1.0.0 'the tag v1.0.0 already exists'
# The newest conveyor/release-suite status is the one that counts: a success under it does not.
case_ status; echo '[{"context":"conveyor/release-suite","state":"failure"},{"context":"conveyor/release-suite","state":"success"}]' > "$STUB/statuses"
refused status 1.1.0 'no passing whole-suite status \(conveyor/release-suite is failure\)'
# A private text added and removed again since the last release is still found, by the commit that added it.
case_ privacy; echo "someone${AT}gmail.com" > "$W/new.txt"; git -C "$W" add -A; git -C "$W" commit -qm add; h=$(git -C "$W" rev-parse HEAD)
git -C "$W" rm -q new.txt; git -C "$W" commit -qm remove; git -C "$W" push -q origin main
refused privacy 1.1.0 "privacy check finds something in commits since v1.0.0: ${h:0:12} "
case_ notes; git -C "$W" rm -q docs/releases/1.1.0.md; git -C "$W" commit -qm drop; git -C "$W" push -q origin main
refused notes 1.1.0 'no release notes: docs/releases/1.1.0.md is missing'

# All checks pass: the tag is on a commit whose plugin.json says 1.1.0 and whose marketplace says v1.1.0; main's
# marketplace pins v1.1.0 at that commit, the other entry untouched; origin has both; the release body is the notes.
case_ pass; rel 1.1.0 || fail "pass: the release was refused: $(cat "$C/out")"
t=$(git -C "$C/origin" rev-parse 'v1.1.0^{commit}' 2>/dev/null) && [ "$(git -C "$C/origin" cat-file -t v1.1.0)" = tag ] || fail "pass: origin has no annotated tag v1.1.0"
[ "$(git -C "$C/origin" show "$t:.claude-plugin/plugin.json" | jq -r .version)" = 1.1.0 ] || fail "pass: plugin.json's version at the tag is not 1.1.0"
[ "$(git -C "$C/origin" show "$t:.claude-plugin/marketplace.json" | jq -c '.plugins[0].source | [.ref, .sha]')" = '["v1.1.0",null]' ] \
  || fail "pass: the marketplace at the tag does not name v1.1.0, or still pins the old sha"
[ "$(git -C "$C/origin" show main:.claude-plugin/marketplace.json | jq -c '[.plugins[].source | [.ref, .sha]]')" = "[[\"v1.1.0\",\"$t\"],[\"v9.0.0\",null]]" ] \
  || fail "pass: main's marketplace does not pin v1.1.0 at the tagged commit $t: $(git -C "$C/origin" show main:.claude-plugin/marketplace.json)"
[ "$(git -C "$C/origin" rev-parse main^)" = "$t" ] || fail "pass: main's marketplace commit is not right on the tagged commit"
grep -q -- '--verify-tag' "$STUB/released" && grep -q '^release create v1.1.0 ' "$STUB/released" && cmp -s "$STUB/body" "$W/docs/releases/1.1.0.md" \
  || fail "pass: the GitHub release is not v1.1.0 with the notes file as its body: $(cat "$STUB/released" 2>&1)"
echo "ok [release]: each refusal says why and changes nothing; a release bumps, pins, tags and releases with its notes"
