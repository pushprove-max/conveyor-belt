#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: the Board on one machine, on the host file setup writes (issue 112). Conveyor and the Board run on
# the same machine; the host file names no build machine. Uses setup.test.sh's sample and doctordone.
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
  mkdir -p "$T/$CASE/bin" "$T/$CASE/home" && printf '#!/bin/sh\necho "$*" >> "%s/ssh-calls"; exit 255\n' "$T/$CASE" > "$T/$CASE/bin/ssh" \
    && chmod +x "$T/$CASE/bin/ssh" || fail "the ssh stub was not made"
  # This machine's Foreman: the sample's marked session, whose transcript is in the default login's folder.
  st=$(cd "$S" && CONVEYOR_MAIN=$S bash "$X" state-dir) && mkdir -p "$st/foreman" "$T/$CASE/home/.claude/projects/p" \
    && echo 'sess-f 2026-11-16T08:00:00Z' > "$st/foreman/session" && : > "$T/$CASE/home/.claude/projects/p/sess-f.jsonl" || fail "the Foreman mark"
  (cd "$S" && HOME=$T/$CASE/home PATH=$T/$CASE/bin:$PATH CONVEYOR_MAIN=$S CONVEYOR_DASHBOARD_DIR=$T/$CASE/dash \
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
