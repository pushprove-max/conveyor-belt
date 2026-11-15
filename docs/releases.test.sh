#!/usr/bin/env bash
# timeout: 60
# The release steps, docs/releases.md (Making a release), hold the step that keeps the Board's built-in model prices
# current: the Claude and OpenAI pricing pages read again, and the table in dashboard_limit.py updated with the date
# read. Bug caught: a release made with last release's prices, so a model newer than it shows as unpriced on the Board.
# Text alone: a release is a person's steps, so there is no behaviour to run; the step's words are what can be checked.
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd -P)
fail() { echo "FAIL [releases]: $*" >&2; exit 1; }
# The numbered steps of Making a release, each with its following lines, one step a record.
steps=$(awk '/^## Making a release/ { on = 1; next } /^## / { on = 0 } on && /^[0-9]+\. / { n++ } on && n { s[n] = s[n] " " $0 }
  END { for (i = 1; i <= n; i++) print s[i] }' "$ROOT/docs/releases.md") || fail "docs/releases.md cannot be read"
[ -n "$steps" ] || fail "docs/releases.md has no numbered steps under Making a release"
grep -i 'claude pricing page' <<<"$steps" | grep -i 'openai pricing page' | grep -F 'dashboard_limit.py' | grep -F 'PRICES' | grep -qi 'date' \
  || fail "no step of Making a release reads the Claude and OpenAI pricing pages again and updates the built-in prices (PRICES, dashboard_limit.py) with the date read"
echo "PASS: releases"
