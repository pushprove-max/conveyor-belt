#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: the machine's service left on older Conveyor than a project's (#185): install-service starts it again
# on the project's commit and checks that its loop runs it (setup and take: setupservice.test.sh); an engine that meets
# a pack field its schema does not name says so in its log, and doctor and health say it of the machine's Conveyor.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# The machine's loop as its service runs it, faked: $STUB/fakeloop <commit> starts a process that stays alive and
# writes MACH/loop.json naming it and <commit>, as machineloop writes it. The systemctl and launchctl stubs run it when
# they start the machine's service, on the commit its unit or agent names, unless $STUB/norestart is there; when
# $STUB/packat names a pack, they first note its tests field as it is then ($STUB/packseen). Each process ends with
# the case. The stubs note every call in $STUB/svc.
fakeloops() {
  mkdir -p "$STUB"
  # It keeps no file of its caller open (the engine's copy of stderr among them): a $( ) that ran the stub would wait
  # for it to end.
  cat > "$STUB/fakeloop" <<'EOF'
#!/usr/bin/env bash
for n in {3..255}; do eval "exec $n>&-"; done
sleep 600 </dev/null >/dev/null 2>&1 & # sleep: the faked loop's process, alive until the case ends it
p=$!; echo "$p" >> "$STUB/pids"
s=$(LC_ALL=C ps -o lstart= -p "$p" | sed 's/^ *//; s/ *$//')
mkdir -p "$XDG_CONFIG_HOME/conveyor/machine"
jq -cn --argjson p "$p" --arg t "$s" --arg c "$1" '{pid: $p, started: $t, commit: $c}' > "$XDG_CONFIG_HOME/conveyor/machine/loop.json"
EOF
  cat > "$STUB/started" <<'EOF'
#!/bin/sh
[ ! -e "$STUB/norestart" ] || exit 0
[ ! -e "$STUB/packat" ] || jq -c '.tests' "$(cat "$STUB/packat")" >> "$STUB/packseen"
exec "$STUB/fakeloop" "$(sed -n 's|.*/versions/\([0-9a-f]\{40\}\)/conveyor/conveyor\.sh.*|\1|p' "$1" | head -1)"
EOF
  printf '#!/bin/sh\necho "systemctl $*" >> "$STUB/svc"\ncase "$*" in "--user restart conveyor-machine.service") exec "$STUB/started" "$XDG_CONFIG_HOME/systemd/user/conveyor-machine.service";; esac\n' > "$STUB/systemctl"
  printf '#!/bin/sh\necho "launchctl $*" >> "$STUB/svc"\ncase "$*" in "bootstrap "*conveyor-machine.plist) exec "$STUB/started" "$3";; print*) exit 1;; esac\n' > "$STUB/launchctl"
  chmod +x "$STUB/fakeloop" "$STUB/started" "$STUB/systemctl" "$STUB/launchctl"
  # A run of these cases under a machine's Conveyor carries its mark, which tells servicerenew it runs inside it.
  unset CONVEYOR_MACHINE_ID
  trap 'kill $(cat "$STUB/pids" 2>/dev/null) 2>/dev/null; chmod -R u+w "$T/$CASE"' EXIT
}

# Bugs: install-service on a new pin rewrote the unit and left the machine's loop running on the old commit, which then
# refused the pack's new fields; it did not say whether the loop runs the new commit. It restarts the unit, checks the
# loop's commit and says so; on the same commit it restarts nothing; a loop that stays on the old commit is said, with
# why and where the log is, and install-service exits non-zero.
t_servicerestart() {
  service_start; fakeloops
  bash "$D/conveyor/conveyor.sh" install "$B" >/dev/null || fail "install of $B failed"
  "$STUB/fakeloop" "$A"; tune --arg c "$B" '.plugin.commit = $c'
  out=$(cd "$R" && bash "$SRC/conveyor.sh" install-service 2>&1) || fail "install-service on a newer pin than the machine's loop exited non-zero: $out"
  grep -qx "systemctl --user restart conveyor-machine.service" "$STUB/svc" && grep -qF "the machine's Conveyor ran Conveyor commit $A, older than $B: started it again on $B" <<<"$out" \
    && grep -qF "the machine's Conveyor runs Conveyor commit $B now (pid " <<<"$out" || fail "the machine's loop on the old commit was not restarted on the new one, or not checked: $out $(cat "$STUB/svc")"
  : > "$STUB/svc"
  (cd "$R" && bash "$SRC/conveyor.sh" install-service >/dev/null 2>&1) || fail "install-service on the commit the loop runs exited non-zero"
  ! grep -q restart "$STUB/svc" || fail "a loop already on the pin was restarted: $(cat "$STUB/svc")"
  "$STUB/fakeloop" "$A"; : > "$STUB/norestart"
  out=$(cd "$R" && CONVEYOR_SERVICE_WAIT=1 bash "$SRC/conveyor.sh" install-service 2>&1) && fail "install-service exited zero with the loop left on the old commit: $out"
  grep -qF "the machine's Conveyor does not run Conveyor commit $B 1 s after its restart: its loop (pid " <<<"$out" \
    && grep -qF "runs Conveyor commit $A; its log: journalctl --user -u conveyor-machine.service" <<<"$out" || fail "a loop left on the old commit was not said, with why: $out"
}
# The same on macOS: the agent names another conveyor.sh, so it is booted out and bootstrapped, not left loaded.
t_servicerestartmac() {
  service_start; fakeloops
  bash "$D/conveyor/conveyor.sh" install "$B" >/dev/null || fail "install of $B failed"
  H=$T/$CASE/home; b=$STUB/brew; mkdir -p "$STUB/mac" "$b/bin" "$H"; printf '#!/bin/sh\necho Darwin\n' > "$STUB/mac/uname"; chmod +x "$STUB/mac/uname"
  ln -s "$(command -v timeout)" "$b/bin/gtimeout"
  for k in coreutils:timeout coreutils:date coreutils:stat findutils:find gnu-sed:sed grep:grep; do
    mkdir -p "$b/opt/${k%%:*}/libexec/gnubin"; ln -s "$(command -v "${k#*:}")" "$b/opt/${k%%:*}/libexec/gnubin/${k#*:}"
  done
  "$STUB/fakeloop" "$A"; tune --arg c "$B" '.plugin.commit = $c'
  out=$(cd "$R" && HOME=$H PATH=$STUB/mac:$b/bin:$PATH bash "$SRC/conveyor.sh" install-service 2>&1) || fail "install-service on macOS on a newer pin exited non-zero: $out"
  [ "$(grep conveyor-machine "$STUB/svc")" = "launchctl bootout gui/$(id -u)/conveyor-machine"$'\n'"launchctl bootstrap gui/$(id -u) $H/Library/LaunchAgents/conveyor-machine.plist" ] \
    && grep -qF "the machine's Conveyor runs Conveyor commit $B now (pid " <<<"$out" || fail "the agent on the old commit was not booted out and loaded on the new one, or not checked: $out $(cat "$STUB/svc")"
}
# Bugs: an engine older than the pack refused a field it did not know with no other sign than its log line every
# 10 s, which did not say the pack was newer nor which commit to run. Its log names the field and the project's commit;
# doctor and health, run by the project's newer engine, say that the machine's Conveyor refuses the pack, the field
# and the commit to start it on.
t_packnewer() {
  export XDG_CONFIG_HOME=$T/$CASE/config; setup '[]'; coderepo; fakeloops
  # O: a commit of the plugin whose schema has no tests field, as one from before it.
  (cd "$D" && jq 'del(.properties.tests)' conveyor/schema/pack.schema.json > "$STUB/s" && cp "$STUB/s" conveyor/schema/pack.schema.json && git commit -qam O && git push -q origin HEAD:main) \
    && O=$(git -C "$D" rev-parse HEAD) && bash "$D/conveyor/conveyor.sh" install "$O" >/dev/null || fail "the old commit was not made"
  tune --arg c "$B" '.plugin.commit = $c | .tests.patterns = ["t/"]'
  out=$(CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards bash "$V/$O/conveyor/conveyor.sh" health 2>&1) && fail "the old engine read a pack with a field it does not know: $out"
  grep -qxF "conveyor pack: $R/.conveyor/project.json: this Conveyor (commit $O) does not know .tests: the pack is for newer Conveyor, commit $B; run conveyor.sh install-service in $R to start the machine's Conveyor on the project's commit" <<<"$out" \
    || fail "the old engine did not name the field and the project's commit: $out"
  # Its doctor stopped at its own pack check, telling the user to correct a pack that is right, with no commit to run.
  out=$(CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards bash "$V/$O/conveyor/conveyor.sh" doctor 2>&1) && fail "the old engine's doctor passed a pack with a field it does not know: $out"
  grep -qxF "missing: a pack this Conveyor reads: this Conveyor (commit $O) does not know .tests: the pack is for newer Conveyor, commit $B; fix: run conveyor.sh install-service in $R to start the machine's Conveyor on the project's commit" <<<"$out" \
    || fail "the old engine's doctor did not name the field and the commit to run: $out"
  # A pack that pins that very engine: the field is a mistake in the pack, not a newer pack.
  out=$(tuned ".plugin.commit = \"$O\"" env CONVEYOR_MAIN="$R" CONVEYOR_CARDS="$T/$CASE/cards" bash "$V/$O/conveyor/conveyor.sh" health 2>&1)
  grep -q '.tests: not a field of the schema' <<<"$out" && ! grep -q 'does not know' <<<"$out" || fail "a field the pinned engine does not know was called a newer pack's: $out"
  "$STUB/fakeloop" "$O"
  [ "$(loop health | jq -c .serviceOld)" = "{\"commit\":\"$O\",\"refused\":\".tests\",\"project\":\"$B\"}" ] || fail "health did not say the machine's Conveyor refuses the pack: $(loop health | jq -c .serviceOld)"
  out=$(loop doctor 2>&1)
  grep -qxF "missing: the machine's Conveyor reading this project's pack: it runs Conveyor commit $O, whose check refuses the pack (.tests), so it does not serve the project; fix: run conveyor.sh install-service in $R, which starts it again on the project's commit $B" <<<"$out" \
    || fail "doctor did not say the machine's Conveyor refuses the pack: $out"
}
