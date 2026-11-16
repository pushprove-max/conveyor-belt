#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# hostfile.sh <checkout> -- the one reader of "which machine and which checkout" in the host file. dashboard.sh
# (hostof, which doctor's Board check runs through dashboard.sh --check), dashboard_server.py (conveyor_host),
# dashboard_stream.py (config) and hooks/units-fetch.sh all ask it, so the Board, its live feed and /units never
# disagree about one file.
# The file: this machine's host file when there is one, else <checkout>'s committed conveyor/host.json.
# Prints one JSON line, {host, local, main, engine, target, records, error}, and exits 0, or {host, local, error} and
# exits 1, where error names the field that is wrong (host is null unless it was read).
#   host     the machine Conveyor runs on
#   local    true on one machine, false with a build machine (even when the rest does not read), null when the
#            file is not there or is not a JSON object
#   main     the checkout of the record the Board steers
#   engine   the checkout whose conveyor/conveyor.sh runs
#   target   the host file's own `ssh` target, null on one machine
#   records  [{repo, main}]: the host file's records, else the one record "project" on main
# One machine: the host file names no ssh target (as setup writes it), or names this machine as its host. Then every
# read runs here: host is the file's host or this machine's name, main is the file's main or <checkout>, and engine is
# this copy of Conveyor (the folder two up from this file). With a build machine, host, main and ssh must all be
# there, and engine is main.
set -uo pipefail
[ $# = 1 ] && [[ $1 == /* ]] || { echo "usage: hostfile.sh <checkout>" >&2; exit 2; }
engine=$(cd "${BASH_SOURCE[0]%/*}/../.." && pwd) || exit 1
cfg=${XDG_CONFIG_HOME:-$HOME/.config}/conveyor/host.json
[ -e "$cfg" ] || cfg=$1/conveyor/host.json
# This machine's short name (the Board's this_host and thishost are this).
name=$(uname -n | cut -d. -f1 | tr -c 'A-Za-z0-9._\n-' -)
[ -e "$cfg" ] || { jq -cn '{host: null, local: null, error: "this checkout has no conveyor/host.json"}'; exit 1; }
out=$(jq -c --arg n "${name:-localhost}" --arg c "$1" --arg e "$engine" '
  def name: strings | select(test("^[A-Za-z0-9._-]+$"));
  def path: strings | select(test("^/[^[:cntrl:]]*$"));
  def ssh: strings | select(test("^[A-Za-z0-9][A-Za-z0-9._@-]*$"));
  def recs($m): (.records // [{repo: "project", main: $m}])
    | if type == "array" and length > 0 and all(type == "object" and (.repo | type == "string" and test("^[A-Za-z0-9._-]+$"))
          and (.main | type == "string" and test("^/[^[:cntrl:]]*$")))
      then map({repo, main}) else null end;
  def done: recs(.main) as $r
    | if $r == null then {host, local, error: "conveyor/host.json records are not understood: each needs a repo name and the path of its main checkout"}
      else . + {records: $r, error: null} end;
  if type != "object" then {host: null, local: null, error: "conveyor/host.json is not a JSON object"}
  elif .ssh == null or .host == $n then
    {host: ((.host | name) // $n), local: true, main: ((.main | path) // $c), engine: $e, target: null, records} | done
  elif ((.host | name) // null) == null then {host: null, local: false, error: "conveyor/host.json names an ssh target, but its host is not a machine name"}
  elif ((.main | path) // null) == null then {host, local: false, error: "conveyor/host.json names no main: the path of the main checkout on \(.host)"}
  elif ((.ssh | ssh) // null) == null then {host, local: false, error: "conveyor/host.json names no ssh target for \(.host) that ssh can use"}
  else {host, local: false, main, engine: .main, target: .ssh, records} | done end' "$cfg" 2>/dev/null)
[ -n "$out" ] || { jq -cn '{host: null, local: null, error: "conveyor/host.json is not a JSON object"}'; exit 1; }
echo "$out"
[[ $out == *'"error":null}' ]]
