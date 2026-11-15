#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases: a project that follows the plugin's releases (plugin.follow "releases"; take(), lib/install.sh): it
# takes the newest published release, never main, a draft or a release whose commit fails its check, and doctor names
# the release it is on and whether a newer one is published.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# A project following releases, beside the plugin's code repo (coderepo, tests/install.test.sh), with $A installed and
# taken by nothing yet. gh lists the releases in $STUB/releases (`gh release list`), each "<tag> <draft>" a line;
# every other gh call goes to the shared stub. Tag v1.0.1 (annotated: its commit is on the peeled line) is $A and
# released; v1.1.0 is $B, a draft; the plugin's main has moved past both, to $M. Not named relsetup: the runner
# sources every case file into one shell, and that is release.test.sh's helper.
followsetup() {
  setup '[]'; coderepo; trap 'chmod -R u+w "$T/$CASE"' EXIT
  tune '.plugin = {follow: "releases"}'
  mv "$STUB/gh" "$STUB/gh.shared" && printf '%s\n' '#!/usr/bin/env bash' \
    '[ "$1 $2" = "release list" ] || exec "$STUB/gh.shared" "$@"' \
    'jq -Rn '"'"'[inputs | split(" ") | {tagName: .[0], isDraft: (.[1] == "draft"), isPrerelease: false}]'"'"' "$STUB/releases"' > "$STUB/gh" \
    && chmod +x "$STUB/gh" || fail "the gh stub was not written"
  git -C "$D" tag -a -m v1.0.1 v1.0.1 "$A" && git -C "$D" tag v1.1.0 "$B" && git -C "$D" push -q origin v1.0.1 v1.1.0 \
    && printf '%s\n' 'v1.0.1 released' 'v1.1.0 draft' > "$STUB/releases" || fail "the tags were not made"
  (cd "$D" && echo 1 > n.txt && git add -A && git commit -qm main && git push -q origin HEAD:main) && M=$(git -C "$D" rev-parse HEAD) \
    || fail "main was not moved past the tags"
  bash "$D/conveyor/conveyor.sh" install "$A" >/dev/null || fail "$A was not installed"
}
# takeby and engine are tests/followmain.test.sh's. doctor's output, run by the install of <commit>:
reldoctor() { (cd "$R" && CONVEYOR_MAIN=$R bash "$V/$1/conveyor/conveyor.sh" doctor 2>&1); } # <commit>

# Bugs: a project that follows releases takes main, where changes are tested before they are released, or a release
# still a draft; it does not move on once a newer release is published; doctor does not name the release it is on.
t_followrelease() {
  followsetup
  out=$(takeby "$A" 2>&1) || fail "the release was not taken: $out"
  [ "$(engine '"\(.commit) \(.release)"')" = "$A v1.0.1" ] || fail "the project did not take v1.0.1 (not main $M, not the draft v1.1.0 $B): $(cat "$R/.git/conveyor-engine.json")"
  grep -q "took Conveyor commit $A of the plugin's release v1.0.1" <<<"$out" || fail "the take did not name the release: $out"
  out=$(reldoctor "$A"); grep -qx "ok: the project follows the plugin's releases: it runs Conveyor commit $A, release v1.0.1, the newest release" <<<"$out" \
    || fail "doctor did not name the release the project is on: $out"
  printf '%s\n' 'v1.0.1 released' 'v1.1.0 released' > "$STUB/releases"
  out=$(takeby "$A" 2>&1) || fail "the published release was not taken: $out"
  [ "$(engine '"\(.commit) \(.release)"')" = "$B v1.1.0" ] || fail "the project did not take v1.1.0 once published: $(cat "$R/.git/conveyor-engine.json")"
}

# Bugs: a release whose commit fails its pack check becomes the project's engine, or is refused and nothing says so;
# doctor does not say a newer release is published.
t_followreleaserefuse() {
  followsetup
  takeby "$A" >/dev/null || fail "v1.0.1 was not taken"
  # v1.2.0: a commit whose schema no longer takes the project's pack, released.
  (cd "$D" && jq '.required += ["zzz"]' conveyor/schema/pack.schema.json > s.new && mv s.new conveyor/schema/pack.schema.json \
    && git commit -qam bad && git tag v1.2.0 && git push -q origin HEAD:main v1.2.0) && E=$(git -C "$D" rev-parse HEAD) \
    && echo 'v1.2.0 released' >> "$STUB/releases" || fail "the failing release was not made"
  out=$(takeby "$A" 2>&1)
  [ "$(engine .commit)" = "$A" ] && [ "$(engine '"\(.refused.commit) \(.refused.release)"')" = "$E v1.2.0" ] \
    || fail "a release that fails its check was taken, or not recorded: $out $(cat "$R/.git/conveyor-engine.json")"
  s=$(loop snapshot) || fail "snapshot exited non-zero"
  jq -e --arg e "$E" '.needsYou.engine | objects | .commit == $e and (.reason | test("its check of the pack failed: .*zzz: missing"))' <<<"$s" >/dev/null \
    || fail "Needs you does not name the refused release's commit and why: $(jq -c .needsYou.engine <<<"$s")"
  out=$(reldoctor "$A"); grep -qx "ok: the project follows the plugin's releases: it runs Conveyor commit $A, release v1.0.1; a newer release is published: v1.2.0 (commit $E)" <<<"$out" \
    || fail "doctor did not say a newer release is published: $out"
}
