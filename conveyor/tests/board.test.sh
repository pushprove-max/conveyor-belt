#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: `conveyor.sh board`, the Board installed as a service (its fixture, service_start: install.test.sh).
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# Bug: the Board was installed from a clone of its own, by four commands typed in turn (find the release, clone it, add
# an admin, install). `conveyor.sh board` alone, in the project's checkout, installs it from the install of the commit
# the project pins, reading that project, and lists the service so prune() keeps the install the Board runs from.
# Bug caught (#108): with no admin yet, board first asked for a typed admin password, so setup's agent could not start
# the Board. It now asks for none (No login on this device lets this machine in), starts the service with no terminal
# and names the address to open. The install's own check (dashboard_server.py can-open) is dashboard-local.test.sh's.
t_board() {
  service_start
  tune --arg c "$A" '.plugin.commit = $c'
  local h=$T/$CASE/home u out py=$XDG_DATA_HOME/conveyor/board-venv/bin/python3
  mkdir -p "${py%/*}" "$h" || fail "the Board's virtualenv was not made"
  # The Board's python3: every call passes (can-open: No login on this device lets this machine in).
  printf '#!/bin/sh\necho "$CONVEYOR_MAIN $*" >> "$STUB/py"\n' > "$py" && chmod +x "$py"
  if [ "$(uname -s)" = Darwin ]; then u=$h/Library/LaunchAgents/com.conveyor.dashboard.plist; else u=$h/.config/systemd/user/dashboard.service; fi
  # Run from the read-only install, as docs/setup.md says: from there the command must act for the checkout it is
  # called in and write no state into the install (it exited before installing anything when it did).
  out=$(cd "$R" && HOME=$h CONVEYOR_DASHBOARD_PORT=8791 bash "$V/$A/conveyor/conveyor.sh" board 2>&1 </dev/null) || fail "board from the install exited non-zero: $out"
  grep -qxF "$R $V/$A/.claude/scripts/dashboard_server.py can-open" "$STUB/py" && ! grep -q ' add-user \| set-password ' "$STUB/py" \
    || fail "board did not check the project's Board from the install it pins, or asked for a password: $(cat "$STUB/py")"
  grep -qF "$V/$A/.claude/scripts/dashboard.sh" "$u" && grep -qF "CONVEYOR_MAIN" "$u" && grep -qF "$R" "$u" \
    || fail "the Board's service does not run the install's Board for the project: $(cat "$u" 2>&1)"
  grep -qx 'systemctl --user restart dashboard.service\|launchctl bootstrap .*com\.conveyor\.dashboard\.plist' "$STUB/svc" \
    || fail "board did not start the Board's service: $(cat "$STUB/svc" 2>&1)"
  grep -qxF "conveyor: the Board runs from $V/$A/.claude/scripts for $R, at https://localhost:8791/" <<<"$out" || fail "board did not name the Board's address: $out"
  grep -qxF "$u" "$XDG_DATA_HOME/conveyor/uses" || fail "the Board's service is not listed, so prune would remove its install: $(cat "$XDG_DATA_HOME/conveyor/uses" 2>&1)"
  # The parts below run on the same fixture (each case pays about 0.5 CPU s for its keeper and service_start), each
  # with a home of its own and its own python3 stub, the stubs' records cleared.
  # Bug caught (#108): with No login on this device off and no admin with a password, the Board cannot be opened, and
  # the only way on was a password typed in a terminal, which setup's agent cannot do. Given the file setup writes from
  # Claude Code's prompt, board adds the admin with that password on stdin (never on a command line), removes the file
  # and starts the service.
  h=$T/$CASE/home2; local pf=$T/$CASE/pw; rm -f "$STUB/py" "$STUB/svc"; mkdir -p "$h" || fail "the second home was not made"
  # The Board's python3: can-open fails until add-user has run; add-user keeps what it read on stdin.
  printf '#!/bin/sh\necho "$CONVEYOR_MAIN $*" >> "$STUB/py"\n[ "$2" != add-user ] || cat > "$STUB/pwin"\n[ "$2" != can-open ] || [ -e "$STUB/pwin" ]\n' > "$py" && chmod +x "$py"
  if [ "$(uname -s)" = Darwin ]; then u=$h/Library/LaunchAgents/com.conveyor.dashboard.plist; else u=$h/.config/systemd/user/dashboard.service; fi
  echo 'pw-example-9e1' > "$pf" || fail "the password file was not made"
  out=$(cd "$R" && HOME=$h bash "$V/$A/conveyor/conveyor.sh" board --password-file "$pf" 2>&1 </dev/null) || fail "board with a password file exited non-zero: $out"
  grep -qxF "$R $V/$A/.claude/scripts/dashboard_server.py add-user admin --admin" "$STUB/py" \
    && [ "$(cat "$STUB/pwin")" = $'pw-example-9e1\npw-example-9e1' ] || fail "board did not add the admin with the password on stdin: $(cat "$STUB/py" "$STUB/pwin" 2>&1)"
  ! grep -q pw-example "$STUB/py" && [[ $out != *pw-example* ]] || fail "the password was on a command line or in board's output"
  [ ! -e "$pf" ] || fail "board left the password file"
  grep -qF "$V/$A/.claude/scripts/dashboard.sh" "$u" && grep -qx 'systemctl --user restart dashboard.service\|launchctl bootstrap .*com\.conveyor\.dashboard\.plist' "$STUB/svc" \
    || fail "board did not start the Board's service: $(cat "$u" "$STUB/svc" 2>&1)"
  # Bug caught (#108): an `admin` added on the account page, its setup link unused, has no password; board's add-user
  # stopped at "admin is already a user" and the Board was not started. board gives that admin the password (on stdin)
  # and the admin role instead, then starts the service.
  h=$T/$CASE/home3; local auth=$T/$CASE/auth.json; rm -f "$STUB/py" "$STUB/svc" "$STUB/pwin"; mkdir -p "$h" || fail "the third home was not made"
  jq -n '{noLoginHere: false, users: {admin: {role: "member", devices: {}}}}' > "$auth" || fail "the login store was not made"
  # The Board's python3: add-user refuses `admin` as the real one does; can-open fails until set-password has run.
  printf '#!/bin/sh\necho "$CONVEYOR_MAIN $*" >> "$STUB/py"\n[ "$2" != add-user ] || { echo "admin is already a user" >&2; exit 1; }\n[ "$2" != set-password ] || cat > "$STUB/pwin"\n[ "$2" != can-open ] || [ -e "$STUB/pwin" ]\n' > "$py" && chmod +x "$py"
  if [ "$(uname -s)" = Darwin ]; then u=$h/Library/LaunchAgents/com.conveyor.dashboard.plist; else u=$h/.config/systemd/user/dashboard.service; fi
  echo 'pw-example-9e1' > "$pf" || fail "the password file was not made"
  out=$(cd "$R" && HOME=$h CONVEYOR_DASHBOARD_AUTH=$auth bash "$V/$A/conveyor/conveyor.sh" board --password-file "$pf" 2>&1 </dev/null) || fail "board for an admin with no password exited non-zero: $out"
  grep -qxF "$R $V/$A/.claude/scripts/dashboard_server.py set-password admin" "$STUB/py" && grep -qxF "$R $V/$A/.claude/scripts/dashboard_server.py set-role admin admin" "$STUB/py" \
    && ! grep -q ' add-user ' "$STUB/py" && [ "$(cat "$STUB/pwin")" = $'pw-example-9e1\npw-example-9e1' ] \
    || fail "board did not give the existing admin the password on stdin and the admin role: $(cat "$STUB/py" "$STUB/pwin" 2>&1)"
  ! grep -q pw-example "$STUB/py" && [ ! -e "$pf" ] || fail "the password was on a command line, or the file was left"
  grep -qx 'systemctl --user restart dashboard.service\|launchctl bootstrap .*com\.conveyor\.dashboard\.plist' "$STUB/svc" \
    || fail "board did not start the Board's service: $(cat "$u" "$STUB/svc" 2>&1)"
}
