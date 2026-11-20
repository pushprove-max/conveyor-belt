#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 60
# The project pack reader (pack.sh) against the schema, on a pack of its own (test-pack.json). A host project's own pack
# is checked by that project's .conveyor/project.test.sh (plan D3).
set -uo pipefail
SRC=$(cd "$(dirname "$0")" && pwd -P)
PACK=$SRC/test-pack.json
SCHEMA=$SRC/../schema/pack.schema.json
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fail() { echo "FAIL [$CASE]: $*" >&2; exit 1; }
pk() { bash "$SRC/pack.sh" "$@"; }
# A copy of the test pack with one jq edit applied.
edited() { jq "$1" "$PACK" > "$T/pack.json" && echo "$T/pack.json"; }

# Bug: a pack missing a required field, top-level or nested, passes the check and the engine reads an empty value.
t_required() {
  for f in $(jq -r '.required[]' "$SCHEMA") labels.built test.command models.allowed.codex; do
    p=$(edited "delpaths([\"$f\" | split(\".\")])")
    out=$(pk check "$p" 2>&1) && fail "a pack without $f passed"
    grep -qF ".$f: missing (required)" <<<"$out" || fail "the failure for a pack without $f does not name it: $out"
    pk get remote "$p" >/dev/null 2>&1 && fail "get read a pack without $f"
  done
  :
}

# Bug: a pack whose field has the wrong type, an unknown (misspelt) field or a value under the schema's minimum passes.
t_mismatch() {
  for e in '.tunables.poll = "30"' '.tunables.poll = 1.5' '.labels.priorities = "P0"' '.push.env.X = 1' '.remote = ""' \
           '.tunables.pol = 30' '.lable = {}' '.tunables.poll = 0' '.productPaths = []'; do
    out=$(pk check "$(edited "$e")" 2>&1) && fail "a pack with $e passed"
    [ -n "$out" ] || fail "a pack with $e failed with no reason"
  done
  out=$(pk check "$(edited '.tunables.pol = 30')" 2>&1); grep -qF '.tunables.pol: not a field of the schema' <<<"$out" || fail "an unknown field is not named: $out"
  echo '{' > "$T/broken.json"; pk check "$T/broken.json" >/dev/null 2>&1 && fail "a pack that is not JSON passed"
  pk check "$T/none.json" >/dev/null 2>&1 && fail "a missing pack passed"
  : > "$T/empty.json"; pk check "$T/empty.json" >/dev/null 2>&1 && fail "an empty pack passed"
  { cat "$PACK"; cat "$PACK"; } > "$T/two.json"; pk check "$T/two.json" >/dev/null 2>&1 && fail "a pack of two JSON documents passed"
  :
}

# Bug: get prints the wrong thing: a string quoted, a list not as JSON, no default for a field left out, or a value
# for a field the schema does not name.
t_get() {
  [ "$(pk get labels.built "$PACK")" = awaiting-deploy ] || fail "labels.built: $(pk get labels.built "$PACK")"
  [ "$(pk get productPaths "$PACK")" = '["src/","shared/","lambdas/","infra/","web/","ml/"]' ] || fail "productPaths: $(pk get productPaths "$PACK")"
  p=$(edited 'del(.tunables, .checks)')
  [ "$(pk get tunables.poll "$p")" = 30 ] || fail "the default of tunables.poll: $(pk get tunables.poll "$p")"
  [ "$(pk get checks "$p")" = '[]' ] || fail "the default of checks: $(pk get checks "$p")"
  [ "$(pk get tunables.closeWait "$(edited '.tunables.closeWait = 0')")" = 0 ] || fail "a set 0 was read as unset"
  # Bug: a default of false (`false // empty` in jq) printed nothing, as if the schema had no default.
  [ "$(pk get test.slowIssues "$(edited 'del(.test.slowIssues)')")" = false ] || fail "the default false of test.slowIssues: $(pk get test.slowIssues "$T/pack.json")"
  [ -z "$(pk get foreman "$PACK")" ] || fail "an unset field with no default printed something"
  pk get tunables.nope "$PACK" >/dev/null 2>&1; [ $? = 2 ] || fail "a field the schema does not name was not refused with exit 2"
  # The pack is found from the current directory's checkout when no path is given.
  git init -q "$T/co" && mkdir -p "$T/co/.conveyor" "$T/co/sub" && jq '.defaultBranch = "trunk"' "$PACK" > "$T/co/.conveyor/project.json"
  [ "$(cd "$T/co/sub" && pk get defaultBranch)" = trunk ] || fail "the default pack location was not found"
}

# Bug: a schema keyword pack.sh does not implement (pattern, here) is silently ignored, so a pack goes unchecked,
# including on an optional field the pack leaves out (foreman.model: the test pack has no foreman).
t_keyword() {
  mkdir -p "$T/lib" "$T/schema"; cp "$SRC/pack.sh" "$T/lib/"
  for e in '.properties.remote.pattern = "^o"' '.properties.foreman.properties.model.pattern = "^x"'; do
    jq "$e" "$SCHEMA" > "$T/schema/pack.schema.json"
    out=$(bash "$T/lib/pack.sh" check "$PACK" 2>&1) && fail "a schema with $e passed"
    grep -qF 'pattern' <<<"$out" || fail "the unchecked keyword of $e is not named: $out"
  done
}

# Bugs: a model's effort range in a seat's pick list (pick.<seat>.<model>) whose min comes after its max, or that
# names an effort no program takes, or a seat that is none, passed the check; a good list, with a bound left out, was
# refused; or the schema's order of the efforts is not the engine's (EFFORTS' opencode list, which holds every effort
# in order: the judge's pick fits an effort to the range by it, PICKCLAMP in modelpick.sh).
t_effort() {
  pk check "$(edited '.pick = {builder: {"claude-opus-5-5": {min: "medium", max: "high"}, "claude-sonnet-5-5": {}}, judge: {"gpt-6-sol": {max: "low"}}}')" >/dev/null || fail "a good pick list was refused"
  out=$(pk check "$(edited '.pick = {builder: {"claude-opus-5-5": {min: "high", max: "low"}}}')" 2>&1) && fail "a range whose min comes after its max passed"
  grep -qF '.pick.builder.claude-opus-5-5: min high comes after max low' <<<"$out" || fail "the reversed range is not named: $out"
  for e in '{reviewer: {m: {min: "huge"}}}' '{fixer: {m: {min: "low"}}}' '{judge: {m: {least: "low"}}}' '{judge: ["m"]}'; do
    pk check "$(edited ".pick = $e")" >/dev/null 2>&1 && fail "a pack with pick $e passed"
  done
  eval "$(grep '^EFFORTS=' "$SRC/paths.sh")"
  [ "$(jq -c '.properties.pick.properties | [.[].additionalProperties.properties[].enum] | unique' "$SCHEMA")" = "[$(jq -c .opencode <<<"$EFFORTS")]" ] \
    || fail "the schema's efforts are not EFFORTS' order: $(jq -c '.properties.pick' "$SCHEMA")"
}

# Bugs: a lint command with both run and size, or neither, passes the check, so the engine reads one as the other or
# runs `null`; a size entry with no limit passes; a good size entry is refused.
t_lintsize() {
  pk check "$(edited '.lint = {commands: [{files: ["*.sh"], size: {file: 400, exempt: ".conveyor/size-exempt"}}]}')" >/dev/null || fail "a good size entry was refused"
  # Each: <the command>|<the failure's text after .lint.commands[0]>.
  for e in '{files: ["*.sh"], run: "x", size: {file: 4, exempt: "e"}}|: both run and size are set: set one' \
           '{files: ["*.sh"]}|: neither run nor size is set: set one' '{files: ["*.sh"], size: {exempt: "e"}}|.size.file: missing (required)'; do
    out=$(pk check "$(edited ".lint = {commands: [${e%%|*}]}")" 2>&1) && fail "a pack with lint command ${e%%|*} passed"
    grep -qF ": .lint.commands[0]${e#*|}" <<<"$out" || fail "the failure for lint command ${e%%|*} does not say ${e#*|}: $out"
  done
}

ALL="required mismatch get keyword effort lintsize"
SEL=${CONVEYOR_SHELL_TEST_CASE:-$ALL}; SEL=${SEL//,/ }
for CASE in $SEL; do case " $ALL " in *" $CASE "*) ;; *) echo "unknown case $CASE" >&2; exit 2 ;; esac; done
for CASE in $SEL; do ( "t_$CASE" ) || exit 1; echo "ok $CASE"; done
