#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 60
# The Foreman's start names foreman.sh by one command whose path is the same in every engine version (lib.sh launcher),
# not by its path in a version folder, and that command runs the project's current engine.
# Bug it catches: the start named foreman.sh by its path in the engine's version folder (in every place it names it, about 1 KB); the
# folder was gone when the Foreman ran the command, because the project's engine had moved to a newer one.
set -uo pipefail
SRC=$(cd "$(dirname "$0")" && pwd -P)
B=$(mktemp -d) || exit 1
trap 'rm -rf "$B"' EXIT
cd "$B" || exit 1
unset CONVEYOR_FOREMAN CONVEYOR_FOREMAN_LAUNCH CONVEYOR_CARD CONVEYOR_LANE CLAUDE_CONFIG_DIR CLAUDE_PROJECT_DIR CONVEYOR_MACHINE_ID
export CLAUDE_PLUGIN_OPTION_boardAutoOpen=false ENG=$SRC/../conveyor.sh
# The ask seam (lib.sh ask): `auto standing <run>` runs the engine on the record's main; any other ask fails.
export CONVEYOR_FOREMAN_ASK='[[ $CONVEYOR_CMD == "auto standing "?* ]] || exit 3; cd "$CONVEYOR_MAIN" && bash "$ENG" auto standing "${CONVEYOR_CMD#auto standing }"'
fail() { echo "FAIL [launcher-$CASE]: $*" >&2; exit 1; }
# fixture <case>: the Foreman's checkout of alpha, which follows the plugin's main and has every standing kind on.
fixture() {
  T=$B/$1 CASE=$1
  export HOME=$T/home XDG_CONFIG_HOME=$T/config XDG_DATA_HOME=$T/data XDG_STATE_HOME=$T/xstate
  M=$T/alpha FD=$T/foreman L=$T/data/conveyor/foreman.sh
  export CONVEYOR_FOREMAN_DIR=$FD CONVEYOR_MAIN=$M
  mkdir -p "$XDG_CONFIG_HOME/conveyor" "$FD" "$M/.conveyor" && git init -q "$M" \
    && jq '.plugin = {follow: "main"} | .auto.standing = ["asked-fix", "review-followup", "release-check", "fixed-block", "review-retry"]' \
      "$SRC/../lib/test-pack.json" > "$M/.conveyor/project.json" \
    && git -C "$M" remote add origin https://example.com/acme/alpha.git \
    && jq -n --arg h "$M" '{records: [{repo: "alpha", main: $h}]}' > "$XDG_CONFIG_HOME/conveyor/host.json" \
    || fail "the fixture was not made"
}
# install <commit>: a version folder whose foreman.sh says which engine ran it; record <commit>: the project's engine record.
install() { mkdir -p "$XDG_DATA_HOME/conveyor/versions/$1/conveyor/foreman" \
  && printf '#!/usr/bin/env bash\necho "engine %s: $*"\n' "$1" > "$XDG_DATA_HOME/conveyor/versions/$1/conveyor/foreman/foreman.sh" || fail "install $1 failed"; }
record() { jq -n --arg c "$1" '{commit: $c}' > "$M/.git/conveyor-engine.json" || fail "the engine record was not made"; }
start() { (cd "$M" && bash "$SRC/foreman.sh" claim sA) || fail "the claim failed"; }

# The start and the standing kinds name the one command, no version-folder path (not the engine's own folder either),
# and the start is shorter than it was with the versioned path in the same places.
t_text() {
  local st old n v=0123456789abcdef0123456789abcdef01234567
  # The fixture's folder is padded to its length in a card's test slot (/tmp/tmp.<x>.tmp/f/tmp.<y>, 40 characters). Bug
  # (#1557): the start, which names the launcher's path in each place, kept its standing kinds at a short /tmp path (and
  # failed only the count below), but went over its limit in the slot and lost its standing kinds.
  local B=$B; [ "${#B}" -ge 39 ] || B+=/$(printf '%*s' $((39 - ${#B})) '' | tr ' ' p)
  fixture text
  st=$(start)
  grep -qF -- '# STANDING YES' <<<"$st" || fail "the start has no standing kinds: $st"
  [ -x "$L" ] || fail "the start did not make $L"
  # Eight places: four in the fixed text (the filing line's `testissue`, the release suite line's `release-run`,
  # `control` and `suite-machine`), one in the standing text all kinds share (the `auto act` line), and one in each of asked-fix,
  # release-check and fixed-block (review-followup and review-retry name no command). The command is counted with its
  # path alone too, so a start that grows or drops a command does not pass on its own copy.
  n=$(grep -oF "$L ask" <<<"$st" | wc -l)
  # The line that sends the Foreman to the plugin's owner-rules.md (a start over its limit, as this one is with the long
  # fixture paths) names the plugin's folder, not a command, so it is left out of the folder check below.
  [ "$n" -eq 8 ] && [ "$(grep -oF "$L" <<<"$st" | wc -l)" -eq 8 ] || fail "the start names $L ask $n times, not the 8 places the versioned path was in: $st"
  ! grep -qE 'versions/|foreman/foreman\.sh|bash [^ ]*foreman\.sh' <<<"$st" && ! grep -vF 'owner-rules.md did not fit' <<<"$st" | grep -qF "$SRC" || fail "the start names a version-folder path: $(grep -E 'versions/|foreman/foreman\.sh|bash [^ ]*foreman\.sh' <<<"$st" | head -3)"
  # Today's text names `bash <data>/conveyor/versions/<commit>/conveyor/foreman/foreman.sh` where it now names $L: the
  # start, with the 8 commands put back, is longer by the paths removed (each over 60 characters).
  old=${st//"$L ask"/"bash $XDG_DATA_HOME/conveyor/versions/$v/conveyor/foreman/foreman.sh ask"}
  [ $((${#old} - ${#st})) -ge $((n * 60)) ] || fail "the start is ${#st} characters, only $((${#old} - ${#st})) shorter than with the versioned path in its $n places"
}

# The command runs foreman.sh of the project's current engine: the engine the record names, from the project's checkout
# or with CONVEYOR_MAIN named; when the engine moves and the version folder that was current is removed, the next run is
# on the new one; and when the folder the project's engine names is gone, it says so and runs nothing.
t_engine() {
  local a=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa b=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb out
  fixture engine
  install "$a"; record "$a"; start > /dev/null
  out=$(cd "$M" && env -u CONVEYOR_MAIN "$L" ask alpha setup 2>&1) && [ "$out" = "engine $a: ask alpha setup" ] || fail "run in the checkout: '$out' is not the engine $a's foreman.sh ask alpha setup"
  out=$(cd "$T" && CONVEYOR_MAIN=$M "$L" ask alpha setup 2>&1) && [ "$out" = "engine $a: ask alpha setup" ] || fail "run with CONVEYOR_MAIN: '$out' is not the engine $a's foreman.sh ask alpha setup"
  install "$b"; record "$b"; chmod -R u+w "$XDG_DATA_HOME/conveyor/versions/$a" && rm -rf "$XDG_DATA_HOME/conveyor/versions/${a:?}"
  out=$(cd "$M" && env -u CONVEYOR_MAIN "$L" ask alpha testissue 2>&1) && [ "$out" = "engine $b: ask alpha testissue" ] || fail "after $a was removed: '$out' is not the engine $b's foreman.sh ask alpha testissue"
  rm -rf "$XDG_DATA_HOME/conveyor/versions/${b:?}"
  out=$(cd "$M" && env -u CONVEYOR_MAIN "$L" ask alpha setup 2>&1) && fail "it ran with no engine installed: $out"
  grep -qF 'is not installed' <<<"$out" || fail "no message that the engine is not installed: $out"
}

cases=(text engine)
# The cases CONVEYOR_SHELL_TEST_CASE names (comma-separated), as the runner selects them; all of them with none set.
SEL=${CONVEYOR_SHELL_TEST_CASE:-${cases[*]}}; SEL=${SEL//,/ }
for c in $SEL; do case " ${cases[*]} " in *" $c "*) ;; *) echo "unknown case $c" >&2; exit 2 ;; esac; done
read -ra cases <<<"$SEL"
for c in "${cases[@]}"; do (t_"$c" && : > "$B/$c.passed") > "$B/$c.out" 2>&1 & done
wait
bad=0
for c in "${cases[@]}"; do cat "$B/$c.out" >&2; [ -e "$B/$c.passed" ] || bad=1; done
[ "$bad" = 0 ] || exit 1
echo "ok [launcher]"
