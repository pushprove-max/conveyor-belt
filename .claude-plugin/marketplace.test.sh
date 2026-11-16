#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 30
# Where users install the plugin from: marketplace.json's plugin entry. It must be a url source with an https:// git
# URL, pinned to a release tag, `ref` of the form vX.Y.Z equal to "v" + plugin.json's version, so users get releases
# only and a version change is what moves them to a new one.
# Bugs: the entry is a github source, or a url source with a git@ or ssh:// URL: Claude Code clones it over SSH, which
# needs a GitHub key even for a public repository, so a user with none cannot install; the entry is a relative ./
# source (or any source with no tag), so every push to main reaches every user; or the tag and plugin.json's version
# differ, so users are pinned to a release other than the one the version names.
set -uo pipefail
DIR=$(cd "$(dirname "$0")" && pwd -P)
fail() { echo "FAIL [marketplace]: $*" >&2; exit 1; }
M=$DIR/marketplace.json
version=$(jq -r '.version // empty' "$DIR/plugin.json")
[[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "plugin.json's version is '$version', want X.Y.Z"
src=$(jq -c '.plugins[] | select(.name == "conveyor-belt") | .source' "$M")
[ -n "$src" ] || fail "no conveyor-belt entry in marketplace.json"
[ "$(jq -r 'type' <<<"$src")" = object ] || fail "the conveyor-belt entry's source is $src, not a url source"
[ "$(jq -r '.source' <<<"$src")" = url ] \
  || fail "the conveyor-belt entry's source is $src, not a url source (a github source clones over SSH)"
url=$(jq -r '.url // empty' <<<"$src")
[[ $url =~ ^https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] \
  || fail "the url source's url is '$url', want https://github.com/<owner>/<repo>.git (any other form can clone over SSH)"
ref=$(jq -r '.ref // empty' <<<"$src")
[[ $ref =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "the url source's ref is '$ref', want vX.Y.Z"
[ "$ref" = "v$version" ] || fail "the url source's ref is '$ref', but plugin.json's version is $version"
# No entry may install from this checkout's files: a relative source is whatever the default branch holds.
rel=$(jq -r '.plugins[] | .source | strings | select(startswith("./") or . == ".")' "$M")
[ -z "$rel" ] || fail "an entry still has a relative source: $rel"
echo "ok [marketplace]: conveyor-belt installs over HTTPS from tag $ref (plugin.json version $version)"
