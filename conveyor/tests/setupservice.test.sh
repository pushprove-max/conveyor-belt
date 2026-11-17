#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: setup and the take command move a project to a newer commit than the machine's service runs (#185),
# and start the service again on it (its fixture, fakeloops: servicerenew.test.sh).
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# Bugs: setup moved the project to a new release and wrote a pack field the machine's loop, on the old commit, did not
# know, so it refused the project every 10 s; setup left that loop running. The loop is restarted on the new commit
# before the field is written, and the check reads the new commit. The take command does the same.
t_setuprestart() {
  local X out; setupdone; export STUB=$T/$CASE/stub; fakeloops; PATH=$STUB:$PATH
  # The new releases are cloned over file://: a clone of a path shares the files of its objects with the clone of
  # $B, which take's prune makes writable again when it removes that install, and the newer installs would then fail
  # their read-only check.
  git -C "$D" remote set-url origin "file://$D.git" || fail "the plugin's origin"
  (cd "$D" && echo >> conveyor/README.md && git commit -qam N && git tag v1.1.0 && git push -q origin HEAD:main v1.1.0) && N=$(git -C "$D" rev-parse HEAD) \
    && echo '[{"tagName":"v1.1.0","isDraft":false,"isPrerelease":false},{"tagName":"v1.0.0","isDraft":false,"isPrerelease":false}]' > "$G/releases" || fail "the new release was not made"
  mkdir -p "$S/src" && echo x > "$S/src/test-a.js" && echo x > "$S/src/test-b.js" && git -C "$S" add src && git -C "$S" -c user.name=t -c user.email=t${AT}example.com commit -qm tests || fail "the test files"
  "$STUB/fakeloop" "$B"; echo "$S/.conveyor/project.json" > "$STUB/packat"
  out=$(cd "$S" && bash "$X" setup --fast-lane no --research-lane no --test-patterns yes 2>&1) || fail "setup that moves to a new release exited non-zero: $out"
  [ "$(jq -r .commit "$S/.git/conveyor-engine.json")" = "$N" ] || fail "setup did not take the new release: $out"
  grep -qx "systemctl --user restart conveyor-machine.service" "$STUB/svc" && grep -qF "the machine's Conveyor runs Conveyor commit $N now (pid " <<<"$out" \
    || fail "setup left the machine's loop on the old commit, or did not check it: $out $(cat "$STUB/svc" 2>/dev/null)"
  [ "$(cat "$STUB/packseen")" = null ] && jq -e '.tests.patterns | length > 0' "$S/.conveyor/project.json" >/dev/null \
    || fail "setup wrote tests before the machine's loop ran the new commit: $(cat "$STUB/packseen") $out"
  # The take command, of the next release: run inside the machine's service (its mark), it says what to run and
  # restarts nothing, as stopping the service would end it first; run again outside, it restarts the loop on it.
  rm "$STUB/packat"; (cd "$D" && echo >> conveyor/README.md && git commit -qam N2 && git tag v1.2.0 && git push -q origin HEAD:main v1.2.0) && N2=$(git -C "$D" rev-parse HEAD) \
    && jq '[{tagName: "v1.2.0", isDraft: false, isPrerelease: false}] + .' "$G/releases" > "$STUB/r" && cp "$STUB/r" "$G/releases" || fail "the next release was not made"
  "$STUB/fakeloop" "$N"; : > "$STUB/svc"
  out=$(cd "$S" && CONVEYOR_MACHINE_ID=1.2 bash "$X" take 2>&1) || fail "take inside the machine's service exited non-zero: $out"
  [ ! -s "$STUB/svc" ] && grep -qF "the machine's Conveyor runs Conveyor commit $N, older than this project's $N2: run conveyor.sh install-service in $S to start it on $N2" <<<"$out" \
    || fail "take inside the machine's service restarted it, or did not say what to run: $out $(cat "$STUB/svc")"
  out=$(cd "$S" && bash "$X" take 2>&1) || fail "take exited non-zero: $out"
  grep -qx "systemctl --user restart conveyor-machine.service" "$STUB/svc" && grep -qF "the machine's Conveyor runs Conveyor commit $N2 now (pid " <<<"$out" \
    || fail "take left the machine's loop on the commit before, or did not check it: $out $(cat "$STUB/svc")"
}

# Bug: with the pack pinned to an older commit whose schema has no tests field, and the service on that commit already
# (so no restart helps), setup wrote tests.patterns anyway, and the engine on that commit refused the whole pack. Each
# field setup writes is checked first by the pinned commit's own pack.sh.
t_setupoldpin() {
  local X out O; setupdone
  (cd "$D" && jq 'del(.properties.tests)' conveyor/schema/pack.schema.json > "$T/$CASE/s" && cp "$T/$CASE/s" conveyor/schema/pack.schema.json \
    && git commit -qam O && git revert --no-edit HEAD >/dev/null && git push -q origin HEAD:main) \
    && O=$(git -C "$D" rev-parse HEAD~1) || fail "the commit with no tests field, and setup's newer one, were not made"
  jq --arg o "$O" '.plugin = {commit: $o}' "$S/.conveyor/project.json" > "$T/$CASE/p" && mv "$T/$CASE/p" "$S/.conveyor/project.json"
  mkdir -p "$S/src" && echo x > "$S/src/test-a.js" && echo x > "$S/src/test-b.js" && git -C "$S" add src && git -C "$S" -c user.name=t -c user.email=t${AT}example.com commit -qm tests || fail "the test files"
  out=$(cd "$S" && bash "$X" setup --fast-lane no --research-lane no --test-patterns yes 2>&1) && fail "setup on a pin with no tests field exited 0: $out"
  ! jq -e 'has("tests")' "$S/.conveyor/project.json" >/dev/null && grep -qF "Conveyor commit $O, which the project runs, cannot read the pack with this field" <<<"$out" \
    || fail "setup wrote tests.patterns into a pack pinned to a commit with no tests field, or did not say why: $out"
}
