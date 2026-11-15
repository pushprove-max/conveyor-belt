#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 30
# Where users install the plugin from: marketplace.json's plugin entry. It must be a github source pinned to a release
# tag, `ref` of the form vX.Y.Z equal to "v" + plugin.json's version, so users get releases only and a version change
# is what moves them to a new one.
# Bugs: the entry is a relative ./ source (or any source with no tag), so every push to main reaches every user; or
# the tag and plugin.json's version differ, so users are pinned to a release other than the one the version names.
set -uo pipefail
DIR=$(cd "$(dirname "$0")" && pwd -P)
fail() { echo "FAIL [marketplace]: $*" >&2; exit 1; }
M=$DIR/marketplace.json
version=$(jq -r '.version // empty' "$DIR/plugin.json")
[[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "plugin.json's version is '$version', want X.Y.Z"
src=$(jq -c '.plugins[] | select(.name == "conveyor-belt") | .source' "$M")
[ -n "$src" ] || fail "no conveyor-belt entry in marketplace.json"
[ "$(jq -r 'type' <<<"$src")" = object ] || fail "the conveyor-belt entry's source is $src, not a github source"
[ "$(jq -r '.source' <<<"$src")" = github ] || fail "the conveyor-belt entry's source is $src, not a github source"
[ -n "$(jq -r '.repo // empty' <<<"$src")" ] || fail "the github source names no repo: $src"
ref=$(jq -r '.ref // empty' <<<"$src")
[[ $ref =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "the github source's ref is '$ref', want vX.Y.Z"
[ "$ref" = "v$version" ] || fail "the github source's ref is '$ref', but plugin.json's version is $version"
# No entry may install from this checkout's files: a relative source is whatever the default branch holds.
rel=$(jq -r '.plugins[] | .source | strings | select(startswith("./") or . == ".")' "$M")
[ -z "$rel" ] || fail "an entry still has a relative source: $rel"
echo "ok [marketplace]: conveyor-belt installs from tag $ref (plugin.json version $version)"
