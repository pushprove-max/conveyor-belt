#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 60
# The Foreman's status (watch-conveyor.sh --status) after the engine a snapshot names stopped runs again. Apart from
# status.test.sh (t_resumed), which is at its 600 lines, with the same fixture.
# Bug caught (R135): a build silent past its limit was stuck before the engine stopped; with the stop it gained
# .stopped (engine), and once the engine ran again the status kept a held entry only for its cases, waits or retry, so
# the silent build was dropped and the status named no stuck card. Health marks such an entry late (views.sh), and the
# status keeps it; #5, stuck only for the stop, is still dropped.
set -uo pipefail
SRC=$(cd "$(dirname "$0")" && pwd -P)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
unset CONVEYOR_FOREMAN CONVEYOR_FOREMAN_LAUNCH CONVEYOR_MAIN CLAUDE_PROJECT_DIR
fail() { echo "FAIL [status-resume]: $*" >&2; exit 1; }
M=$T/alpha
export XDG_CONFIG_HOME=$T/config XDG_DATA_HOME=$T/data HOME=$T/home CONVEYOR_FOREMAN_DIR=$T/state/foreman
export CONVEYOR_FOREMAN_NOW; CONVEYOR_FOREMAN_NOW=$(jq -n '"2026-11-15T12:00:00Z" | fromdate')
mkdir -p "$XDG_CONFIG_HOME/conveyor" "$HOME" "$M/.conveyor" && git init -q "$M" && echo '{}' > "$M/.conveyor/project.json" \
  && jq -n --arg s "$T/state" --arg m "$M" '{stateDir: $s, records: [{repo: "alpha", main: $m}]}' > "$XDG_CONFIG_HOME/conveyor/host.json" \
  || fail "the fixture was not made"
export CONVEYOR_FOREMAN_ASK="cat $T/snap"
# The engine, pid 4242, runs now: `ps -o stat= -p 4242` prints S; any other ps call is the real one.
mkdir -p "$T/bin" && printf '#!/usr/bin/env bash\n[ "$*" = "-o stat= -p 4242" ] && { echo S; exit 0; }\nexec %q "$@"\n' "$(command -v ps)" > "$T/bin/ps" \
  && chmod +x "$T/bin/ps" || fail "the ps stub was not made"
export PATH=$T/bin:$PATH
jq -n '{belt: [], queue: {next: [{issue: 99}], waiting: []}, open: {held: []}, suites: [],
  health: {time: "2026-11-15T12:00:00Z", loop: true, gh: true, blocked: [], waiting: [], pushFailingSince: null,
    engineStopped: {pid: 4242, since: "2026-11-15T11:40:00Z", pids: [4242]},
    stuck: [{card: "c5", issue: 5, step: "build", since: "2026-11-15T11:38:00Z", stopped: {pid: 4242, of: "engine", since: "2026-11-15T11:40:00Z"}},
      {card: "c10", issue: 10, step: "build", since: "2026-11-15T11:00:00Z", late: true, stopped: {pid: 4242, of: "engine", since: "2026-11-15T11:40:00Z"}}]}}' > "$T/snap" \
  || fail "the snapshot was not made"
out=$(CONVEYOR_MAIN=$M bash "$SRC/watch-conveyor.sh" --status 2>&1) || fail "the status failed: $out"
grep -qxF 'needs you: #10 is stuck: no new step and no output since 2026-11-15T11:00:00Z (last step: build)' <<<"$out" \
  || fail "with the engine running again (ps S) and #10's build silent since 11:00 (late), the status drops #10: $out"
! grep -qF '#5' <<<"$out" || fail "with the engine running again, the status still names #5, stuck only for the stop: $out"
echo "ok [status-resume]"
