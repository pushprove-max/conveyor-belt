#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 30
# The Claude Code versions the plugin states it runs on: plugin.json's engines["claude-code"]. Claude Code does not
# install, update or load a plugin outside that range, so it must be exactly ">=2.1.322": a valid range whose floor is
# 2.1.322, the oldest version the Conveyor has run on.
# Bugs: the range is missing or is not a range, so older Claude Code loads the plugin and hits hooks it lacks; or the
# range shuts out 2.1.322, so users on a version the Conveyor runs on cannot install it.
set -uo pipefail
DIR=$(cd "$(dirname "$0")" && pwd -P)
WANT='>=2.1.322'
range=$(jq -r '.engines["claude-code"]' "$DIR/plugin.json")
[ "$range" = "$WANT" ] || { echo "FAIL [plugin]: engines[\"claude-code\"] is '$range', want '$WANT'" >&2; exit 1; }
echo "ok [plugin]: engines[\"claude-code\"] is '$WANT'"
