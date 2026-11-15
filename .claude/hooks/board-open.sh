#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# SessionStart hook (the plugin's, through shim.sh, which hooks/hooks.json calls only in a repo with a pack): opens the Board in the browser when a session starts fresh in a
# repo with a Conveyor pack. The /plugin config option boardAutoOpen (on by default) reaches hooks only, as
# CLAUDE_PLUGIN_OPTION_boardAutoOpen; "false" turns this off. Only the startup source opens it: a resume, clear or
# compact would stack another tab. Card sessions never get here: they run with --setting-sources "" and the engine's
# card settings, which carry no plugin hook.
# The URL is the Board's page server on this machine: https://localhost:<port>/, or https://<this host>.local:<port>/
# when the host file says {"board": {"lan": true}}. Nothing opens unless the port answers with the Board's login page,
# under the Board's own certificate; when nothing listens there, one line says the Board is not running. The check and
# the opener (open on macOS, xdg-open elsewhere) run in the background, holding the session half a second at most.
#
# Self-test: bash .claude/hooks/__tests__/board-open.test.sh
set -uo pipefail

INPUT=$(cat)
[ "${CLAUDE_PLUGIN_OPTION_boardAutoOpen:-true}" != false ] || exit 0
[ "$(jq -r '.source // empty' <<<"$INPUT" 2>/dev/null)" = startup ] || exit 0
ROOT=${CLAUDE_PROJECT_DIR:-$(jq -r '.cwd // empty' <<<"$INPUT")}
[ -f "${ROOT:-.}/.conveyor/project.json" ] || exit 0

# The Board's port, read as dashboard.sh reads it.
PORT=${CONVEYOR_DASHBOARD_PORT:-8790}
HOST_FILE=${XDG_CONFIG_HOME:-$HOME/.config}/conveyor/host.json
name=localhost
[ "$(jq -r '.board.lan // false' "$HOST_FILE" 2>/dev/null)" != true ] || name=$(hostname -s).local
url=https://$name:$PORT/

# Only the Board's own login page counts: another service on the port is not the Board. The connection must present
# the Board's own self-signed certificate, found where dashboard_server.py keeps it (beside the login store), so
# another HTTPS service cannot pass by serving the same page. -q (it must come first) skips the user's curl
# configuration, whose `insecure` would drop that check. The check runs in the background and opens the tab itself
# once the page answers; the session waits half a second at most for its verdict, so a listener that answers slowly or
# never (a full accept queue) cannot hold the start. A port with nothing listening refuses at once, so that case is
# named in one line; a slower verdict is not waited for, and nothing opens unless it is the Board.
AUTH=${CONVEYOR_DASHBOARD_AUTH:-$(dirname "${CONVEYOR_RULING_LOG:-$HOME/.claude/rulings/conveyor.jsonl}")/dashboard-auth.json}
opener=xdg-open; [ "$(uname -s)" != Darwin ] || opener=open
# The check keeps none of the session's streams, so the hook's end is not held by it.
exec 3< <(
  exec </dev/null 2>/dev/null
  page=$(curl -q -s --cacert "$(dirname "$AUTH")/dashboard-tls/cert.pem" --max-time 2 "https://127.0.0.1:$PORT/login")
  if [[ $page == *'<title>Conveyor Board</title>'* ]]; then ( "$opener" "$url" >/dev/null & ); echo board
  else echo none; fi
)
read -r -t 0.5 -u 3 verdict || verdict=
[ "$verdict" != none ] || echo "conveyor: the Board is not running (nothing serves $url), so it was not opened"
exit 0
