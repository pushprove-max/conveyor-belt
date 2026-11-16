#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: the Board on one machine, on the host file setup writes (issue 112). Conveyor and the Board run on
# the same machine; the host file names no build machine. Also a Board left on older engine code than the project's
# after an update (issue 134). Uses setup.test.sh's sample and doctordone.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# Bug caught (#112): the Board read only a host file that named a build machine (host, main and ssh). The host file
# setup writes names none, so on a one-machine install every panel said the Board could not read the build machine.
# After setup, the Board's collection reads every record here: every panel's part has data and no error, Health names
# this machine, and nothing is asked over ssh. Doctor reads setup's host file with the Board's own reader.
t_boardone() {
  local X out n st; doctordone
  out=$(cd "$S" && bash "$X" doctor 2>&1)
  n=$(uname -n | cut -d. -f1 | tr -c 'A-Za-z0-9._\n-' -)
  grep -qx "ok: the Board reads the project on this machine ($n)" <<<"$out" || fail "doctor did not find setup's host file read by the Board: $out"
  # ssh fails the case's run if anything asks for it; the Board's usage reads find no login in the case's home.
  mkdir -p "$T/$CASE/bin" "$T/$CASE/h" && printf '#!/bin/sh\necho "$*" >> "%s/ssh-calls"; exit 255\n' "$T/$CASE" > "$T/$CASE/bin/ssh" \
    && chmod +x "$T/$CASE/bin/ssh" || fail "the ssh stub was not made"
  # This machine's Foreman: the sample's marked session, whose transcript is in the default login's folder.
  st=$(cd "$S" && CONVEYOR_MAIN=$S bash "$X" state-dir) && mkdir -p "$st/foreman" "$T/$CASE/h/.claude/projects/p" \
    && echo 'sess-f 2026-11-16T08:00:00Z' > "$st/foreman/session" && : > "$T/$CASE/h/.claude/projects/p/sess-f.jsonl" || fail "the Foreman mark"
  (cd "$S" && HOME=$T/$CASE/h PATH=$T/$CASE/bin:$PATH CONVEYOR_MAIN=$S CONVEYOR_DASHBOARD_DIR=$T/$CASE/dash \
    timeout 120 bash "$D/.claude/scripts/dashboard.sh" > "$T/$CASE/dash.out" 2>&1) || fail "the Board's collection failed: $(tail -n 5 "$T/$CASE/dash.out")"
  [ ! -e "$T/$CASE/ssh-calls" ] || fail "the Board asked over ssh on one machine: $(cat "$T/$CASE/ssh-calls")"
  sed 's/^[^{]*//; s/;[[:space:]]*$//' "$T/$CASE/dash/data.js" > "$T/$CASE/data.json" || fail "no data.js"
  jq -e '[.panels | to_entries[] | select(.value.error != null or .value.data == null) | .key] == []' "$T/$CASE/data.json" >/dev/null \
    || fail "a panel did not read on one machine: $(jq -c '[.panels | to_entries[] | select(.value.error != null or .value.data == null) | {(.key): .value.error}]' "$T/$CASE/data.json")"
  jq -e --arg n "$n" '.panels.health.data.host | .local == true and .name == $n and .reachable == true and .error == null' "$T/$CASE/data.json" >/dev/null \
    || fail "Health does not show this machine: $(jq -c '.panels.health.data.host' "$T/$CASE/data.json")"
  jq -e '.panels.belt.data | type == "object"' "$T/$CASE/data.json" >/dev/null || fail "no belt part"
  # Bug caught: on one machine every account was listed as the host's, whose rows never read the Foreman mark, so the
  # login the Foreman runs on said "not used by the Conveyor".
  jq -e '.panels.health.data.accounts.list | map(select(.name == "default"))[0].usedFor | index("this machine'"'"'s Foreman") != null' "$T/$CASE/data.json" >/dev/null \
    || fail "the Foreman's login is not shown as this machine's Foreman: $(jq -c '.panels.health.data.accounts' "$T/$CASE/data.json")"
}
# Bug caught (#134): /units read the host file by rules of its own, which needed a host and a main, so on the host
# file setup writes (records alone) units-fetch.sh printed `host <tab><tab>config 0` and /units showed no card or
# cost, while the Board read the same file. Every reader asks hostfile.sh: the Board's check, its page server, its live
# feed and the /units fetch give this machine, this copy of Conveyor and setup's records, and the fetch in the main
# checkout returns the sample's snapshot.
t_boardonereaders() {
  local X n out want; doctordone
  n=$(uname -n | cut -d. -f1 | tr -c 'A-Za-z0-9._\n-' -)
  want=$(jq -c --arg n "$n" --arg e "$D" '[$n, null, $e, (.records | map({(.repo): .main}) | add)]' "$XDG_CONFIG_HOME/conveyor/host.json") || fail "setup's host file"
  out=$(cd "$S" && CONVEYOR_MAIN=$S timeout 120 bash "$D/.claude/scripts/dashboard.sh" --check 2>&1) || fail "the Board's check failed: $out"
  [ "${out##*$'\n'}" = "on this machine ($n)" ] || fail "the Board's check did not read this machine: $out"
  # The case's Board virtualenv is a stub: the page server's login packages, which reading the host file never uses,
  # are empty modules here.
  out=$(cd "$S" && CONVEYOR_MAIN=$S python3 -I - "$D/.claude/scripts" "$S" 2>&1 <<'PY'
import json, sys, types
sys.path.insert(0, sys.argv[1])
for m in ('pyotp', 'segno', 'cryptography', 'cryptography.fernet'):
    sys.modules[m] = types.ModuleType(m)
sys.modules['cryptography.fernet'].Fernet = None
import dashboard_server, dashboard_stream
h, t, e, r = dashboard_server.conveyor_host()
print(json.dumps([h, t, e, r], separators=(',', ':')))
cfg, why = dashboard_stream.config(sys.argv[2])
print(json.dumps(why) if why else json.dumps([cfg[0], cfg[3], cfg[4], dict(cfg[2])], separators=(',', ':')))
PY
  ) || fail "the page server's or the live feed's read failed: $out"
  [ "$out" = "$want"$'\n'"$want" ] || fail "the page server and the live feed do not read setup's host file as one machine: want $want, got $out"
  # The plugin's fetch (the case's code copy has no hooks/), which snapshots by its own copy of Conveyor.
  out=$(cd "$S" && timeout 120 bash "$SRC/../hooks/units-fetch.sh" 2>&1) || fail "units-fetch.sh failed: $out"
  grep -qxF "$(printf 'host\t%s\tlocal\t0' "$n")" <<<"$out" || fail "/units did not read this machine: $out"
  jq -e --arg r "$(jq -r '.records[0].repo' "$XDG_CONFIG_HOME/conveyor/host.json")" -R 'select(startswith($r + "\t")) | sub("^[^\t]*\t"; "") | fromjson
    | (.belt | type == "array") and (.cost | type == "object")' <<<"$out" >/dev/null || fail "/units got no snapshot of setup's record: $out"
}
# Bug caught: doctor's Board check passed a host file whose record gives no snapshot (its main is no checkout), only
# checking that the engine file exists, and every panel then said it could not read. The check reads every record.
t_boardonedead() {
  local X out; doctordone
  jq --arg m "$T/$CASE/gone" '.records += [{repo: "gone", main: $m}]' "$XDG_CONFIG_HOME/conveyor/host.json" > "$T/$CASE/h" \
    && mv "$T/$CASE/h" "$XDG_CONFIG_HOME/conveyor/host.json" || fail "host file"
  out=$(cd "$S" && CONVEYOR_MAIN=$S timeout 120 bash "$D/.claude/scripts/dashboard.sh" --check 2>&1) && fail "the Board's check passed with a record that gives no snapshot: $out"
  grep -q 'answered, but its Conveyor gave no snapshot' <<<"$out" || fail "the check did not say why the Board cannot read the project: $out"
}
# Bug caught: setup records the checkout's path as it is, but the Board took only paths of letters, digits and ._/-,
# so a checkout in a folder with a space had a host file the Board did not understand.
t_boardonespace() {
  local X out; sample; X=$D/conveyor/conveyor.sh
  mv "$S" "$T/$CASE/my project" && S="$T/$CASE/my project" || fail "the sample was not moved"
  (cd "$S" && bash "$X" setup --fast-lane no --research-lane no --owner Dana --product src/ --test t --survey no --pin >/dev/null) || fail "setup exited non-zero"
  jq -e --arg m "$S" 'any(.records[]; .main == $m)' "$XDG_CONFIG_HOME/conveyor/host.json" >/dev/null || fail "setup wrote no record of the checkout"
  out=$(cd "$S" && CONVEYOR_MAIN=$S timeout 120 bash "$D/.claude/scripts/dashboard.sh" --check 2>&1) || fail "the Board did not read a checkout whose path has a space: $out"
  grep -qx "on this machine ($(uname -n | cut -d. -f1 | tr -c 'A-Za-z0-9._\n-' -))" <<<"$out" || fail "the check did not name this machine: $out"
}
# Bug caught (#112): a host file the Board cannot read gave every panel "could not read the build machine" and doctor
# said nothing. Doctor fails and names the field that is wrong: an ssh target with no host name.
t_boardonebad() {
  local X out; doctordone
  jq '.ssh = "user@far"' "$XDG_CONFIG_HOME/conveyor/host.json" > "$T/$CASE/h" && mv "$T/$CASE/h" "$XDG_CONFIG_HOME/conveyor/host.json" || fail "host file"
  out=$(cd "$S" && bash "$X" doctor 2>&1) && fail "doctor passed with a host file the Board cannot read: $out"
  grep -qF "missing: the Board reading the project (conveyor/host.json names an ssh target, but its host is not a machine name); fix: correct the host file $XDG_CONFIG_HOME/conveyor/host.json as that says" <<<"$out" \
    || fail "doctor did not name why the Board cannot read the project: $out"
}

# oldboard -- a Board loop left running from the install of the commit before the pin ($A), as after an update: a
# process whose command is a bash running VERSIONS/$A/.claude/scripts/dashboard.sh --loop, as the Board's service
# starts it. It ends on TERM. Its pid is OLDB; it is stopped when the case ends.
oldboard() {
  printf '%s\n' '#!/usr/bin/env bash' 'sleep 300 & s=$!' "trap 'kill \$s; exit 0' TERM" 'wait' > "$T/$CASE/bash"  # sleep: the stand-in Board runs until it is stopped
  chmod +x "$T/$CASE/bash" || fail "the old Board's stand-in was not made"
  "$T/$CASE/bash" "$V/$A/.claude/scripts/dashboard.sh" --loop & OLDB=$!
  trap 'chmod -R u+w "$T/$CASE"; kill "$OLDB" 2>/dev/null' EXIT
  wait_until "ps -o args= -p $OLDB | grep -q -- 'dashboard.sh --loop'" || fail "the old Board's stand-in did not start"
}
# Bug caught (#134): setup left a Board running on the engine before the update. That Board could not read the host
# file setup writes, so it showed no card for hours, and nothing restarted it. Setup starts it again on the
# project's install: the Board's service is written for the pinned commit and restarted, and the old loop, which no
# service runs, is stopped.
t_boardoneold() {
  local X out h=$T/$CASE/home; sample; X=$D/conveyor/conveyor.sh; oldboard
  # The Board's service is this case's own: its home, and a systemctl that records each call.
  mkdir -p "$h" "$T/$CASE/bin" && printf '#!/bin/sh\necho "systemctl $*" >> "%s/svc"\n' "$T/$CASE" > "$T/$CASE/bin/systemctl" \
    && chmod +x "$T/$CASE/bin/systemctl" || fail "the systemctl stub was not made"
  out=$(cd "$S" && HOME=$h PATH=$T/$CASE/bin:$PATH CONVEYOR_HOST_OS=Linux \
    bash "$X" setup --fast-lane no --research-lane no --owner Dana --product src/ --test t --survey no --pin 2>&1) || fail "setup failed: $out"
  grep -qxF "conveyor: the Board runs Conveyor commit $A, older than this project's $B: starting it again on $B" <<<"$out" \
    || fail "setup did not find the Board on the old engine: $out"
  grep -qF "\"$V/$B/.claude/scripts/dashboard.sh\" --loop" "$h/.config/systemd/user/dashboard.service" 2>/dev/null \
    && grep -qx 'systemctl --user restart dashboard.service' "$T/$CASE/svc" \
    || fail "the Board's service was not restarted on the pinned commit: $(cat "$h/.config/systemd/user/dashboard.service" "$T/$CASE/svc" 2>&1)"
  wait_until "! kill -0 $OLDB 2>/dev/null" || fail "the old Board loop still runs after setup: $out"
}
# Bug caught (#134): doctor said `ok: the Board, running` for a Board on older engine code than the project's, which
# could not read the host file. It names both commits and the fix.
t_boardoneolddoctor() {
  local X out; doctordone; oldboard
  out=$(cd "$S" && bash "$X" doctor 2>&1) && fail "doctor passed with a Board on older engine code: $out"
  grep -qxF "missing: the Board runs engine $A but the project has $B; fix: run /conveyor-belt:setup, which starts it again on $B, or conveyor.sh board in the project's checkout" <<<"$out" \
    || fail "doctor did not flag the Board on older engine code: $out"
}
