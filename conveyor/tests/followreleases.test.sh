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

# The plugin's repository, $G, as https://github.com/example-owner/plugin (git reads that address from $G:
# url.insteadOf), holding its manifest and engine folder, with one published release, v1.0.0 at $H, and main past it
# at $M. gh answers `release list` with v1.0.0 only for the repository in $GHREPO. plugrel/plugmain run
# releaseof/mainof for the plugin folder <folder>, as an engine there would. Names no other case file uses: the runner
# sources every case file into one shell.
plugfixture() {
  local c=$T/$CASE w=$T/$CASE/w
  G=$c/plugin.git U=https://github.com/example-owner/plugin; mkdir -p "$c/bin" || fail "the case folder was not made"
  export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=url.$G.insteadOf GIT_CONFIG_VALUE_0=$U
  printf '%s\n' '#!/usr/bin/env bash' '[ "$1 $2 $3 $4" = "release list -R $GHREPO" ] || exit 1' \
    "echo '[{\"tagName\": \"v1.0.0\", \"isDraft\": false, \"isPrerelease\": false}]'" > "$c/bin/gh" && chmod +x "$c/bin/gh" \
    || fail "the gh stub was not written"
  git init -q --bare -b main "$G" && git clone -q "$G" "$w" 2>/dev/null && mkdir -p "$w/.claude-plugin" "$w/conveyor" \
    && jq -n --arg u "$U" '{name: "plugin", repository: $u}' > "$w/.claude-plugin/plugin.json" && touch "$w/conveyor/x" \
    && git -C "$w" add -A && git -C "$w" commit -qm one && git -C "$w" tag v1.0.0 && H=$(git -C "$w" rev-parse HEAD) \
    && git -C "$w" commit -q --allow-empty -m two && M=$(git -C "$w" rev-parse HEAD) && git -C "$w" push -q origin main v1.0.0 \
    || fail "the plugin's repository was not made"
}
plugrel() { (HERE=$1/conveyor OWN=''; PATH=$T/$CASE/bin:$PATH; export GHREPO; . "$SRC/lib/install.sh"; releaseof); } # <folder>
# shellcheck disable=SC2034 # HERE and OWN are read by mainof, from the sourced lib/install.sh
plugmain() { (HERE=$1/conveyor OWN=''; . "$SRC/lib/install.sh"; mainof main); } # <folder>

# Bugs: a plugin installed from its marketplace runs from a copy with no .git, so it has no origin and its releases
# (and main) could not be read; one in a config folder kept in git reads that repository's origin as the plugin's; when
# no source names the repository, the message does not say which sources were read.
t_releasecache() {
  plugfixture; GHREPO=$U; local c=$T/$CASE P=$T/$CASE/cache/plugin/1.0.0
  # The cache copy sits in a repository of its own whose origin is not the plugin's.
  git init -q -b main "$c" && git -C "$c" remote add origin "$c/other.git" && mkdir -p "$P" \
    && git -C "$c/w" archive v1.0.0 | tar -x -C "$P" || fail "the cache copy was not made"
  [ "$(plugrel "$P")" = "$U"$'\t'"$H"$'\t'v1.0.0 ] || fail "the release was not read from the repository plugin.json names: $(plugrel "$P" 2>&1)"
  [ "$(plugmain "$P")" = "$U"$'\t'"$M" ] || fail "main was not read from the repository plugin.json names: $(plugmain "$P" 2>&1)"
  # No repository in plugin.json: the marketplace entry for the plugin names it, as owner/repo.
  jq -n '{name: "plugin"}' > "$P/.claude-plugin/plugin.json" \
    && jq -n '{plugins: [{name: "other", source: {source: "github", repo: "example-owner/other"}}, {name: "plugin", source: {source: "github", repo: "example-owner/plugin"}}]}' \
      > "$P/.claude-plugin/marketplace.json" || fail "the manifests were not written"
  [ "$(plugrel "$P")" = "$U"$'\t'"$H"$'\t'v1.0.0 ] || fail "the release was not read from the repository the marketplace entry names: $(plugrel "$P" 2>&1)"
  rm "$P/.claude-plugin/marketplace.json"
  out=$(plugrel "$P" 2>&1) && fail "a release was read with no source naming the repository: $out"
  grep -qF "$P is no clone with an origin, and neither $P/.claude-plugin/plugin.json (repository) nor $P/.claude-plugin/marketplace.json (the plugin's source.repo) names one on GitHub" <<<"$out" \
    || fail "the message did not say which sources were read: $out"
}

# Bug: a plugin clone reads its repository from its manifest, not from its origin, where its releases are.
t_releaseclone() {
  plugfixture; GHREPO=$G
  [ "$(plugrel "$T/$CASE/w")" = "$G"$'\t'"$H"$'\t'v1.0.0 ] || fail "the clone did not read its release from its origin: $(plugrel "$T/$CASE/w" 2>&1)"
}
