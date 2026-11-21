#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 60
# hostfile.sh, the one reader of "which machine and which checkout" in the host file (issue 134). Bug caught: the
# Board, its live feed and /units each read the host file by rules of their own, and /units's needed a host and a
# main, so on the host file setup writes (records alone) /units showed no card while the Board did. Each case below
# is one host file; conveyor/tests/boardone.test.sh (t_boardone) has every reader read setup's own.
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
READER=$HERE/../hostfile.sh ENGINE=$(cd "$HERE/../../.." && pwd)
T=$(mktemp -d) || exit 1
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/config/conveyor" "$T/main/conveyor" "$T/empty"
ME=$(uname -n | cut -d. -f1 | tr -c 'A-Za-z0-9._\n-' -) fails=0 n=0
bad() { echo "FAIL [hostfile]: $1" >&2; fails=$((fails + 1)); }
# read <case> <host file or -> <want: the reader's line> <want: its exit>; - is no host file of this machine.
read_is() {
  local got rc=0; n=$((n + 1))
  if [ "$2" = - ]; then rm -f "$T/config/conveyor/host.json"; else printf '%s\n' "$2" > "$T/config/conveyor/host.json"; fi
  got=$(XDG_CONFIG_HOME=$T/config bash "$READER" "$T/main") || rc=$?
  [ "$got" = "$3" ] && [ "$rc" = "$4" ] || bad "$1: got $got (exit $rc), want $3 (exit $4)"
}
one() { jq -cn --arg h "$ME" --arg m "$T/main" --arg e "$ENGINE" --argjson r "$1" '{host: $h, local: true, main: $m, engine: $e, target: null, records: $r, error: null}'; }

# The host file setup writes on one machine: records alone. This machine, this checkout, this copy of Conveyor.
read_is setup_one_machine '{"records":[{"repo":"p","main":"/srv/my p"}],"claudeProxy":{"baseUrl":"x"}}' "$(one '[{"repo":"p","main":"/srv/my p"}]')" 0
# This machine named as the host, with an ssh target: still one machine (the target is not used).
read_is this_machine_named "{\"host\":\"$ME\",\"ssh\":\"me@$ME\",\"records\":[{\"repo\":\"p\",\"main\":\"/srv/p\"}]}" \
  "$(one '[{"repo":"p","main":"/srv/p"}]')" 0
# No records: the one record "project", on main (here, this checkout).
read_is no_records '{}' "$(one "$(jq -cn --arg m "$T/main" '[{repo: "project", main: $m}]')")" 0
# A build machine: host, main and ssh, and the engine is the host's main.
read_is build_machine '{"host":"far","ssh":"me@far","main":"/srv/m"}' \
  '{"host":"far","local":false,"main":"/srv/m","engine":"/srv/m","target":"me@far","records":[{"repo":"project","main":"/srv/m"}],"error":null}' 0
# A build machine the file does not say all of is still not this machine (local false): the Board says so.
read_is build_machine_no_main '{"host":"far","ssh":"me@far"}' '{"host":"far","local":false,"error":"conveyor/host.json names no main: the path of the main checkout on far"}' 1
read_is build_machine_no_host '{"ssh":"me@far","main":"/srv/m"}' '{"host":null,"local":false,"error":"conveyor/host.json names an ssh target, but its host is not a machine name"}' 1
read_is bad_ssh_target '{"host":"far","ssh":"-oProxyCommand=x","main":"/srv/m"}' '{"host":"far","local":false,"error":"conveyor/host.json names no ssh target for far that ssh can use"}' 1
read_is bad_record '{"records":[{"repo":"a b","main":"/srv/p"}]}' \
  "{\"host\":\"$ME\",\"local\":true,\"error\":\"conveyor/host.json records are not understood: each needs a repo name and the path of its main checkout\"}" 1
read_is not_json 'nope' '{"host":null,"local":null,"error":"conveyor/host.json is not a JSON object"}' 1
# No host file of this machine: the checkout's committed one, else none.
echo '{"records":[{"repo":"c","main":"/srv/c"}]}' > "$T/main/conveyor/host.json"
read_is the_checkouts_file - "$(one '[{"repo":"c","main":"/srv/c"}]')" 0
rm "$T/main/conveyor/host.json"
read_is no_file - '{"host":null,"local":null,"error":"this checkout has no conveyor/host.json"}' 1

# The readers ask hostfile.sh, and none decides the machine, the checkout or the ssh target by itself. This one check
# is of the files' text: a reader with rules of its own can give the same answer on every file a test writes, so only
# its source shows it (bug: four copies of the rules, and units-fetch.sh's drifted from the Board's).
n=$((n + 1))
# The server's reading moved to dashboard_server_control.py (#1134): it must ask hostfile.sh; dashboard_server.py is still scanned for rules.
for f in .claude/scripts/dashboard.sh .claude/scripts/dashboard_server.py .claude/scripts/dashboard_server_control.py .claude/scripts/dashboard_stream.py hooks/units-fetch.sh; do
  [ "$f" = .claude/scripts/dashboard_server.py ] || grep -q 'hostfile\.sh' "$ENGINE/$f" || bad "$f does not ask hostfile.sh"
  hits=$(grep -nE "\.ssh *(\||//|!=|==)|\.host *(\||!=|==)|\.main *\| *(strings|select)|cfg\.get\(.(ssh|host|main).\)|uname -n|nodename" "$ENGINE/$f")
  [ -z "$hits" ] || bad "$f reads the host file's machine or checkout by itself: $hits"
done
# doctor reads it by the Board's own reader, dashboard.sh --check.
grep -q '"$f" --check' "$ENGINE/conveyor/lib/setup.sh" || bad "doctor does not read the host file by dashboard.sh --check"
[ "$fails" = 0 ] || exit 1
echo "PASS: hostfile ($n checks)"
