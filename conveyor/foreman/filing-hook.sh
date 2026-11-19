#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# filing-hook.sh filing | filed -- the plugin's hook line for foreman.sh filing (PreToolUse, Bash) and filed
# (PostToolUse and PostToolUseFailure, Bash), run from the plugin copy itself (hooks/hooks.json). Nearly every Bash
# call files no issue, and for one the two have nothing to do, so this reads the hook's input whole and ends at once,
# printing nothing, when its command files no issue (files.jq, the test foreman.sh files makes): the shim's look for
# the project's engine, and the engine, never start. Any other input goes on to `shim.sh conveyor/foreman/foreman.sh
# <filing | filed>` whole, which tests it again with the engine's own files.jq. Both hooks of a call run this same
# copy, so a filing it lets through has its filed too.
set -u
case ${1:-} in filing | filed) ;; *) echo "usage: filing-hook.sh filing | filed" >&2; exit 2 ;; esac
in=$(cat)
jq -e -f "${BASH_SOURCE[0]%/*}/files.jq" <<<"$in" >/dev/null 2>&1 || exit 0
exec "${BASH_SOURCE[0]%/*}/../../shim.sh" conveyor/foreman/foreman.sh "$1" <<<"$in"
