#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 30
# The DCO check (dco.sh) on a fixture pull request. Bugs it catches: a pull request with a commit that has no
# sign-off passes; a commit signed off by someone other than its author passes; the failure does not name the
# commit, so the contributor cannot tell which one to fix; a pull request whose commits are all signed off fails;
# an unsigned merge commit (which can carry conflict fixes) passes; a signed-off merge commit fails.
set -uo pipefail
DIR=$(cd "$(dirname "$0")" && pwd -P)
fail() { echo "FAIL [dco]: $*" >&2; exit 1; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
A=ada@users.noreply.github.com
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME='Ada Example' GIT_AUTHOR_EMAIL=$A \
  GIT_COMMITTER_NAME='Ada Example' GIT_COMMITTER_EMAIL=$A
g() { git -C "$T" "$@"; }
commit() { echo "$1" >> "$T/a.txt" && g add a.txt && g commit -q -m "$1" "${@:2}" && g rev-parse HEAD; }
g init -q -b main && commit base > /dev/null || fail "the fixture repository could not be made"
BASE=$(g rev-parse HEAD)

# All signed: two commits, each with its author's sign-off.
commit one -s > /dev/null && SIGNED=$(commit two -s) || fail "the signed commits could not be made"
out=$(cd "$T" && bash "$DIR/dco.sh" "$BASE" "$SIGNED" 2>&1) || fail "a pull request with every commit signed off failed: $out"

# One unsigned commit on top, and one signed off by another person than its author.
UNSIGNED=$(commit three) && OTHER=$(commit four -m 'Signed-off-by: Bo Example <bo@users.noreply.github.com>') \
  || fail "the unsigned commits could not be made"
out=$(cd "$T" && bash "$DIR/dco.sh" "$BASE" "$OTHER" 2>&1); rc=$?
[ "$rc" = 1 ] || fail "a pull request with an unsigned commit did not fail with 1 (exit $rc): $out"
grep -qF "commit ${UNSIGNED:0:7}" <<<"$out" && grep -qF '"three"' <<<"$out" \
  || fail "the failure does not name the unsigned commit ${UNSIGNED:0:7}: $out"
grep -qF "commit ${OTHER:0:7}" <<<"$out" || fail "a commit signed off by another person passed: $out"
! grep -qF "${SIGNED:0:7}" <<<"$out" || fail "a signed commit was named as unsigned: $out"
# Merge commits: a signed side commit merged without a sign-off fails, naming the merge; with --signoff it passes.
g checkout -q -b side "$SIGNED" && echo side > "$T/b.txt" && g add b.txt && g commit -q -s -m side \
  && g checkout -q -b merged "$SIGNED" && echo merged > "$T/c.txt" && g add c.txt && g commit -q -s -m merged \
  && g merge -q --no-ff --no-edit side && MERGE=$(g rev-parse HEAD) || fail "the unsigned merge could not be made"
out=$(cd "$T" && bash "$DIR/dco.sh" "$BASE" "$MERGE" 2>&1); rc=$?
[ "$rc" = 1 ] && grep -qF "commit ${MERGE:0:7}" <<<"$out" \
  || fail "a pull request with an unsigned merge commit did not fail naming it (exit $rc): $out"
g reset -q --hard HEAD~1 && g merge -q --no-ff --no-edit --signoff side || fail "the signed merge could not be made"
out=$(cd "$T" && bash "$DIR/dco.sh" "$BASE" HEAD 2>&1) || fail "a pull request with a signed-off merge commit failed: $out"
echo "ok [dco]: the check passes signed commits and merges and fails, by name, an unsigned commit, an unsigned merge and one signed off by another"
