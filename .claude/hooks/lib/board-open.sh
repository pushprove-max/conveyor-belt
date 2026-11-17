#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Sourced, never run. board_open <the project's main checkout>: opens the Board in the browser, once, starting it
# first when nothing serves its port. Sourced by the SessionStart hook board-open.sh (a fresh start) and by
# `foreman.sh claim` (a session made the Foreman), so both open it by the same check, start and opener. The /plugin
# config option boardAutoOpen (on by default), as CLAUDE_PLUGIN_OPTION_boardAutoOpen; "false" turns it off. The caller
# decides when to call it: each call can open one tab.
# The URL is always https://localhost:<port>/ (the port read as dashboard.sh reads it): "No login on this device" lets
# this machine in there with no password, and no other name is opened. Nothing opens unless the port answers with the
# Board's login page, under the Board's own certificate. When nothing listens there, `conveyor.sh board` starts the
# Board from the checkout (CONVEYOR_BOARD_START_CMD, when set, runs in its place), its output goes to a file, one line
# says so and names the file, and the tab opens once the Board answers. The check, the start and the opener (open on
# macOS, xdg-open elsewhere) run in the background, holding the caller half a second at most.
board_open() {
  [ "${CLAUDE_PLUGIN_OPTION_boardAutoOpen:-true}" != false ] || return 0
  local port=${CONVEYOR_DASHBOARD_PORT:-8790} auth opener=xdg-open url verdict log here
  here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
  auth=${CONVEYOR_DASHBOARD_AUTH:-$(dirname "${CONVEYOR_RULING_LOG:-$HOME/.claude/rulings/conveyor.jsonl}")/dashboard-auth.json}
  url=https://localhost:$port/
  [ "$(uname -s)" != Darwin ] || opener=open
  # Only the Board's own login page counts: another service on the port is not the Board. The connection must present
  # the Board's own self-signed certificate, found where dashboard_server.py keeps it (beside the login store), so
  # another HTTPS service cannot pass by serving the same page. -q (it must come first) skips the user's curl
  # configuration, whose `insecure` would drop that check. curl's exit 7 is a refused connection: nothing listens, so
  # the Board is down and is started; any other service on the port is left alone. Before the first start there is no
  # certificate yet, and curl refuses a --cacert file that does not exist (exit 2), so /dev/null is passed in its place:
  # a closed port still gives 7. A TLS or certificate failure (a listener that fails the check) is "cert <curl exit>".
  board_page_() {
    local page rc ca
    ca=$(dirname "$auth")/dashboard-tls/cert.pem
    [ -f "$ca" ] || ca=/dev/null
    page=$(curl -q -s --cacert "$ca" --max-time 2 "https://127.0.0.1:$port/login"); rc=$?
    case $rc in
      0) [[ $page == *'<title>Conveyor Board</title>'* ]] && echo board || echo none ;;
      7) echo down ;;
      35|51|53|54|58|59|60|64|66|77|80|82|83|90|91) echo "cert $rc" ;;
      *) echo none ;;
    esac
  }
  # The check runs in the background and opens the tab itself once the page answers; the caller waits half a second
  # at most for its verdict, so a listener that answers slowly or never (a full accept queue) cannot hold it. A port
  # with nothing listening refuses at once, so that case is named in one line; a slower verdict is not waited for,
  # and nothing opens unless it is the Board. The check keeps none of the caller's streams, so the caller's end is not
  # held by it.
  exec 3< <(
    exec </dev/null 2>/dev/null
    verdict=$(board_page_); echo "$verdict"
    [ "$verdict" != board ] || ( "$opener" "$url" >/dev/null & )
  )
  read -r -t 0.5 -u 3 verdict || verdict=
  exec 3<&-
  case $verdict in
    none) echo "conveyor: the Board is not running (nothing serves $url), so it was not opened" ;;
    cert\ *) echo "conveyor: something answers on $url but fails the check of the Board's certificate (curl exit ${verdict#cert }), so it was not opened; fix: run conveyor.sh board in the project's checkout, which replaces a certificate that does not name its curve and restarts the Board" ;;
    down)
      log=$(mktemp "${TMPDIR:-/tmp}/conveyor-board-start.XXXXXX") || log=/dev/null
      echo "conveyor: the Board is not running (nothing serves $url), so conveyor.sh board starts it; it opens when it answers (the start's output: $log)"
      # The start, then up to a minute for the Board to answer, in the background with none of the caller's streams.
      (
        exec </dev/null >"$log" 2>&1
        cd "${1:-.}" || exit 1
        if [ -n "${CONVEYOR_BOARD_START_CMD:-}" ]; then bash -c "$CONVEYOR_BOARD_START_CMD"
        else "$BASH" "$here/../../../conveyor/conveyor.sh" board; fi || exit 1
        for _ in {1..60}; do
          [ "$(board_page_ 2>/dev/null)" != board ] || { "$opener" "$url" >/dev/null 2>&1; exit 0; }
          sleep 1 # sleep: the started Board's server takes a moment to listen
        done
        echo "conveyor: the Board did not answer on $url within a minute, so it was not opened"
      ) &
      ;;
  esac
  return 0
}
