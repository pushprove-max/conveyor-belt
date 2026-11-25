#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 60
# The Foreman's start (foreman.sh, its claim's context) names each standing kind of routine yes the pack turns on
# (auto.standing, conveyor/lib/standing.sh), with its limits, and no kind that is off.
# Bug it catches: the kinds were only in one project's own Foreman notes, so no other install's Foreman acted on them,
# and a kind the owner turned off was still acted on; and the start read the kinds from the Foreman's own checkout, not
# from the record's pack on the host that runs its belt, where the Board turns them on or off.
set -uo pipefail
SRC=$(cd "$(dirname "$0")" && pwd -P)
B=$(mktemp -d) || exit 1
trap 'rm -rf "$B"' EXIT
cd "$B" || exit 1
unset CONVEYOR_FOREMAN CONVEYOR_FOREMAN_LAUNCH CONVEYOR_CARD CONVEYOR_LANE CLAUDE_CONFIG_DIR CLAUDE_PROJECT_DIR CONVEYOR_MACHINE_ID
export CLAUDE_PLUGIN_OPTION_boardAutoOpen=false ENG=$SRC/../conveyor.sh
# The ask seam (lib.sh ask): `auto standing <run>` and `auto standing <kind> how` run the engine on the record's main,
# as on its host, with the arguments the real ask gives (<run> is one argument, with spaces); any other ask fails.
export CONVEYOR_FOREMAN_ASK='[[ $CONVEYOR_CMD == "auto standing "?* ]] || exit 3; cd "$CONVEYOR_MAIN" || exit 1; r=${CONVEYOR_CMD#auto standing }
if [[ $r =~ ^([a-z-]+)\ how$ ]]; then bash "$ENG" auto standing "${BASH_REMATCH[1]}" how; else bash "$ENG" auto standing "$r"; fi'
fail() { echo "FAIL [standing-$CASE]: $*" >&2; exit 1; }
# pack <checkout> <kinds>: a git checkout with the test pack, its auto.standing <kinds> (a json list).
pack() {
  git init -q "$1" && mkdir -p "$1/.conveyor" \
    && jq --argjson k "$2" '.plugin = {follow: "main"} | .auto.standing = $k' "$SRC/../lib/test-pack.json" > "$1/.conveyor/project.json"
}
# fixture <case> <kinds>: the Foreman's own checkout of alpha here, and alpha's record, its main on the host ($H, the
# checkout the ask seam runs on), as in the setup where the Foreman runs on the owner's machine and the belt on a host.
# The record's pack has <kinds>; this checkout's pack has every kind when <kinds> is empty, else none, so the start
# shows whose pack it read.
fixture() {
  T=$B/$1 CASE=$1
  export HOME=$T/home XDG_CONFIG_HOME=$T/config XDG_DATA_HOME=$T/data XDG_STATE_HOME=$T/xstate
  M=$T/alpha H=$T/host/alpha FD=$T/foreman
  export CONVEYOR_FOREMAN_DIR=$FD CONVEYOR_MAIN=$M
  mkdir -p "$XDG_CONFIG_HOME/conveyor" "$FD" && pack "$H" "$2" \
    && pack "$M" "$(jq -c 'if length == 0 then ["asked-fix", "review-followup", "release-check", "fixed-block", "review-retry"] else [] end' <<<"$2")" \
    && git -C "$M" remote add origin https://example.com/acme/alpha.git \
    && jq -n --arg h "$H" '{records: [{repo: "alpha", main: $h}]}' > "$XDG_CONFIG_HOME/conveyor/host.json" \
    || fail "the fixture was not made"
}
start() { (cd "$M" && bash "$SRC/foreman.sh" claim sA) || fail "the claim failed"; } # the claim prints the start's context
# The line each kind's rule starts with.
line() { echo "- $1: "; }
kinds=(asked-fix review-followup release-check fixed-block review-retry)

# One kind on: its rule and the limits are in the start, and no other kind's rule is. The start is left in $out.
one() { # <kind>
  local k
  fixture "$1" "[\"$1\"]"; out=$(start)
  grep -qF '# STANDING YES' <<<"$out" && grep -qF -- "$(line "$1")" <<<"$out" \
    && grep -qF -- '- Still ask the owner, whatever the kind: new engine behaviour' <<<"$out" || fail "the start does not name the kind $1 that is on: $out"
  for k in "${kinds[@]}"; do [ "$k" = "$1" ] || ! grep -qF -- "$(line "$k")" <<<"$out" || fail "the start names $k, which is off: $out"; done
}
t_askedfix() { one asked-fix; }
t_reviewfollowup() { one review-followup; }
t_releasecheck() { one release-check; }
t_fixedblock() { one fixed-block; }
# #715: the start names the kind the watcher acts on, and leaves its act to the watcher. Bug it catches: the start told
# the Foreman to take, log and report each kind that is on, so it would retry and log the watcher's cards a second time.
t_reviewretry() {
  one review-retry
  grep -qF 'Take each one without asking (but review-retry, which the watcher takes itself)' <<<"$out" \
    && grep -qF 'you take no step for it, log nothing and tell the owner nothing of it' <<<"$out" \
    || fail "the start gives the watcher's review-retry to the Foreman: $out"
}
# Every kind off (the list setup writes): the start names no standing kind.
# And its role line sends to the owner only what the still-ask list and the project's rules name. Bug it catches
# (#1678): the line said "take every decision to the owner", so the Foreman waited for the owner on decisions its
# rules let it take, and blocked cards sat until the owner asked. The list the line names is in the start with no kind
# on too: auto.standing is empty by default, and a start that left the list out pointed the Foreman at nothing.
t_none() {
  local out; fixture none '[]'; out=$(start)
  local role; role=$(grep '^# Foreman mode: you are' <<<"$out") || fail "no Foreman start: $out"
  # The wording is checked on the role line itself: on a line after it, it would not be the Foreman's role.
  grep -qF 'clear blocked cards the same turn; ask only what "Still ask the owner" or rules name; never build or answer for them' <<<"$role" \
    && ! grep -qF 'take every decision to the owner' <<<"$out" || fail "the start's role line does not limit what goes to the owner to the still-ask list and the rules: $role"
  grep -qF -- '- Still ask the owner, whatever the kind: new engine behaviour' <<<"$out" || fail "the start with no kind on has no still-ask list for its role line to name: $out"
  ! grep -qE 'STANDING YES|WARNING: the standing' <<<"$out" || fail "the start names standing kinds while none is on: $out"
}
# The host cannot be asked: one warning names the record, and no kind is taken, not even this checkout's.
t_unread() {
  local out; fixture unread '[]'; out=$(CONVEYOR_FOREMAN_ASK='exit 3' start)
  grep -qF '# WARNING: the standing kinds of routine yes of alpha could not be read' <<<"$out" \
    && ! grep -qF 'STANDING YES' <<<"$out" || fail "the start took kinds it could not read from the record: $out"
}

# The command the start gives for logging an act reaches the record where its pack is (foreman.sh ask, by the real
# lib.sh ask, its engine the one the record's install runs), not this checkout, whose pack has the kind off.
# Bug it catches: the rules named the host's engine path with no way to the host, so the Foreman, on its own machine,
# ran them against its own checkout: refused there, or logged in the wrong project.
# And the start must still tell the Foreman to log an act: the command that logs it is read from the start's own words
# (a start that dropped the instruction, or its `auto act <kind>` form, leaves nothing to run).
t_act() {
  local out run act c=0123456789abcdef0123456789abcdef01234567
  fixture act '["asked-fix"]'; out=$(start)
  run=$(sed -n 's/.*Run each command after `\([^`]*\)`\..*/\1/p' <<<"$out")
  act=$(sed -n 's/.*Log each act with `\(auto act <kind> [^`]*\)`.*/\1/p' <<<"$out")
  [[ $run == *"$XDG_DATA_HOME/conveyor/foreman.sh ask alpha"* ]] || fail "the start's act command does not reach the record alpha: $out"
  [ -n "$act" ] || fail "the start does not tell the Foreman to log an act with auto act <kind>: $out"
  mkdir -p "$XDG_DATA_HOME/conveyor/versions/$c" && ln -s "$SRC/.." "$XDG_DATA_HOME/conveyor/versions/$c/conveyor" \
    && jq -n --arg c "$c" '{commit: $c}' | tee "$M/.git/conveyor-engine.json" > "$H/.git/conveyor-engine.json" || fail "the record's install was not made"
  export CONVEYOR_RULING_LOG=$T/rulings.jsonl
  out=$(cd "$T" && unset CONVEYOR_FOREMAN_ASK && eval "$run ${act//<kind>/asked-fix}" 2>&1) \
    && [ "$(jq -r .kind "$CONVEYOR_RULING_LOG")" = asked-fix ] && [ "$(jq -r .answer "$CONVEYOR_RULING_LOG")" = '<what you did, with the issue or card>' ] \
    || fail "the start's act command ($run ${act//<kind>/asked-fix}) did not log the act in the record: $out"
}
# The rest of the release-check and review-retry rules, which the start names by a command, is asked of the record's
# host, as the rules are: the engine that printed the rule prints its rest. The ask seam logs each ask it gets.
# Bug it catches (review of #1638): the rules sent the Foreman to foreman.sh procedures, which the Foreman's own engine
# prints; with the belt on a host whose engine is newer than the Foreman's machine's, that engine had no such text.
t_how() {
  local out out2 run k cmd c=0123456789abcdef0123456789abcdef01234567
  fixture how '["release-check", "review-retry"]'; out=$(start)
  run=$(sed -n 's/.*Run each command after `\([^`]*\)`\..*/\1/p' <<<"$out")
  mkdir -p "$XDG_DATA_HOME/conveyor/versions/$c" && ln -s "$SRC/.." "$XDG_DATA_HOME/conveyor/versions/$c/conveyor" \
    && jq -n --arg c "$c" '{commit: $c}' > "$M/.git/conveyor-engine.json" || fail "the Foreman's install was not made"
  for k in release-check review-retry; do
    cmd=$(grep -F -- "- $k: " <<<"$out" | grep -oF "\`auto standing $k how\`" | tr -d '`')
    [ -n "$cmd" ] && [ -n "$run" ] || fail "the start's $k rule names no auto standing $k how command, or no command to run it with: $out"
    out2=$(cd "$T" && CONVEYOR_FOREMAN_ASK="echo \"\$CONVEYOR_REPO \$CONVEYOR_MAIN \$CONVEYOR_CMD\" >> $(printf %q "$T/asked"); $CONVEYOR_FOREMAN_ASK" eval "$run $cmd" 2>&1) \
      && [ "$out2" = "$(cd "$H" && bash "$ENG" auto standing "$k" how)" ] && [ -n "$out2" ] \
      && grep -qxF "alpha $H auto standing $k how" "$T/asked" \
      || fail "the start's command ($run $cmd) did not print the rest of the $k rule from the record's host: $out2; asked: $(cat "$T/asked" 2>&1)"
  done
}

cases=(askedfix reviewfollowup releasecheck fixedblock reviewretry none unread act how)
# The cases CONVEYOR_SHELL_TEST_CASE names (comma-separated), as the runner selects them; all of them with none set.
SEL=${CONVEYOR_SHELL_TEST_CASE:-${cases[*]}}; SEL=${SEL//,/ }
for c in $SEL; do case " ${cases[*]} " in *" $c "*) ;; *) echo "unknown case $c" >&2; exit 2 ;; esac; done
read -ra cases <<<"$SEL"
for c in "${cases[@]}"; do (t_"$c" && : > "$B/$c.passed") > "$B/$c.out" 2>&1 & done
wait
. "$SRC/tests/casesreport-helper.sh"
casesreport "$B" standing- "${cases[@]}" || exit 1
echo "ok [standing]"
