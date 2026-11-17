#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: cores kept for the user (issue 196; the host file's reserveCores, lib/slots.sh slot_reserved, slot_keep,
# slot_reserve_why, slot_cpus, steer_words): no test slot is on a kept core, no card session or test run runs on one,
# and doctor and health name the kept cores and the slots left, or why the machine cannot keep cores.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# The case's own host file, as the engine reads it, with <json> merged in; steer_on (lib/paths.sh) read with it.
reserve_host() { # <json>
  HOST=$XDG_CONFIG_HOME/conveyor/host.json
  mkdir -p "${HOST%/*}" && jq -n "$1" > "$HOST" || fail "the host file could not be written"
  eval "$(sed -n '/^steer_on() {/p' "$SRC/lib/paths.sh")"
}
# The cores a process may run on, one a line, from taskset's list ("0-3,6").
cpus_of() { # <pid>
  local l x i r
  l=$(taskset -cp "$1") || return 1; l=${l##*: }; IFS=, read -ra r <<<"$l"
  for x in "${r[@]}"; do for ((i = ${x%-*}; i <= ${x#*-}; i++)); do echo "$i"; done; done
}

# Bugs it catches: the test-slot pool handed out every core, so card tests took the cores the user types on; and the
# pool's size was not cut to the cores left, so two slots shared one core. With reserveCores 2 the pool has no slot on
# the two highest-numbered cores, each slot's worker is pinned off them (slot_mine), and the pool is no larger than the
# cores left. A list keeps the cores it names; a number of every core still leaves core 0 for card work.
t_reservepool() {
  local d=$T/$CASE n k c cs
  command -v taskset >/dev/null || return 0
  n=$(nproc --all); [ "$n" -ge 3 ] || return 0
  mkdir -p "$d/pool"
  reserve_host "{testSlotsDir: \"$d/pool\", testSlots: 100000, reserveCores: 2}"
  ( unset CONVEYOR_TEST_POOL CONVEYOR_TEST_SLOT; slot_pool || fail "slot_pool failed"
    [[ " $SLOT_CPUS" != *" $((n - 1)) "* && " $SLOT_CPUS" != *" $((n - 2)) "* ]] || fail "the pool's cores hold a kept core: $SLOT_CPUS (of $n)"
    read -ra cs <<<"$SLOT_CPUS"; [ "${#cs[@]}" -ge 1 ] && [ "$SLOT_N" = "${#cs[@]}" ] && [ "$SLOT_N" -le $((n - 2)) ] \
      || fail "the pool has $SLOT_N slots on cores $SLOT_CPUS, not one a core left ($((n - 2)) at most)"
    # shellcheck disable=SC2034 # SLOT_ENV and SLOT_K are read by slot_mine
    SLOT_ENV=x
    # shellcheck disable=SC2034
    for ((k = 1; k <= SLOT_N; k++)); do
      c=$(SLOT_K=$k; slot_mine && cpus_of "$BASHPID") || fail "slot $k's worker was not pinned"
      [ "$c" != $((n - 1)) ] && [ "$c" != $((n - 2)) ] && [[ $c =~ ^[0-9]+$ ]] || fail "slot $k's worker runs on core $c, a kept one"
    done ) || exit 1
  reserve_host '{reserveCores: [0]}'
  [ "$(slot_reserved | paste -sd, -)" = 0 ] && [[ " $(slot_cpus | paste -sd' ' -) " != *' 0 '* ]] || fail "a named core is not kept: $(slot_reserved | paste -sd, -)"
  reserve_host "{reserveCores: $((n + 5))}"
  [ "$(slot_keep)" = 0 ] || fail "keeping more cores than the machine has left $(slot_keep) to card work, not core 0"
  reserve_host '{reserveCores: 0}'
  [ -z "$(slot_reserved)" ] && ! slot_keep >/dev/null || fail "reserveCores 0 keeps cores: $(slot_reserved | paste -sd, -)"
}

# Bugs it catches: a card session or test run ran on the cores kept for the user. The builder (an OpenCode session,
# through the words every session uses, steer_words session) runs on the cores left, with steer on and with it off
# (the cores are kept either way); a test run's words (steer_words test) start it on the cores left too.
t_reservesession() {
  # shellcheck disable=SC2034 # BUILD_TIMEOUT is read by builder()
  local d=$T/$CASE STEER STEER_HOW STEER_SLICE BUILD_TIMEOUT=30 n s c
  command -v taskset >/dev/null || return 0
  n=$(nproc --all); [ "$n" -ge 3 ] || return 0
  mkdir -p "$d/bin" "$d/wt"
  # opencode stands in for every session's program: it writes the cores it may run on beside the worktree.
  printf '%s\n' '#!/usr/bin/env bash' 'taskset -cp $$ > "$PWD.cpus"; cat > /dev/null' > "$d/bin/opencode"; chmod +x "$d/bin/opencode"
  eval "$(sed -n '/^builder() {/,/^}/p' "$SRC/lib/session.sh")"
  for s in none false; do
    reserve_host "{reserveCores: 2} + (if \"$s\" == \"none\" then {} else {steer: false} end)"
    steer_words session; rm -f "$d/wt.cpus"
    ( PATH=$d/bin:$PATH; builder "$d/wt" prompt opencode:p/m '' '' opencode ) || fail "the builder did not run: $(cat "$d/wt.err" 2>&1)"
    c=$(sed 's/.*: //' "$d/wt.cpus") && [ -n "$c" ] || fail "the session did not say its cores"
    [ "$c" = "$(slot_keep)" ] || [ "$c" = "0-$((n - 3))" ] || fail "with steer $s the session runs on cores $c, not those left (0-$((n - 3)))"
  done
  reserve_host '{reserveCores: 2}'
  steer_words test
  c=$("${STEER[@]}" bash -c 'taskset -cp $$' 2>&1 | sed 's/.*: //'); steer_end
  [ "$c" = "0-$((n - 3))" ] || [ "$c" = "$(slot_keep)" ] || fail "a test run runs on cores $c, not those left (0-$((n - 3))): ${STEER[*]}"
}

# Bug it catches: on a machine that cannot keep a process off a core (macOS: no taskset) the setting read as in
# force. There no core is kept, the words of a session name no taskset, and slot_reserve_why says why.
t_reservemac() {
  # shellcheck disable=SC2034 # STEER_HOW and STEER_SLICE are set by steer_words
  local d=$T/$CASE STEER STEER_HOW STEER_SLICE t out
  mkdir -p "$d/bin"
  for t in jq nproc bash; do ln -s "$(command -v "$t")" "$d/bin/$t" || fail "no $t"; done
  reserve_host '{reserveCores: 2}'
  out=$(PATH=$d/bin OSTYPE=darwin23; slot_reserve_why; echo "kept:$(slot_reserved)"; slot_keep && echo keep; steer_words session; echo "words:${STEER[*]}")
  [ "$out" = $'macOS lets no program keep a process off a core\nkept:\nwords:nice -n 10' ] || fail "on macOS the setting is not shown as not available, or a core is kept: $out"
}

# Bugs it catches: neither doctor nor health (the Board's Rules tab) said which cores are kept for the user, nor how
# many test slots the cores left hold.
t_reservedoctor() {
  setup '[]'
  local H=$XDG_CONFIG_HOME/conveyor/host.json out n
  command -v taskset >/dev/null || return 0
  n=$(nproc --all); [ "$n" -ge 3 ] || return 0
  mkdir -p "${H%/*}"
  jq -n --arg r "$R" '{records: [{repo: "solo", main: $r}], reserveCores: 2}' > "$H"
  out=$(loop health | jq -c .cores)
  jq -e --argjson n "$n" '.reserved == [$n - 2, $n - 1] and (.slots | type == "number" and . >= 1 and . <= $n - 2) and .unavailable == null' <<<"$out" >/dev/null \
    || fail "health does not name the kept cores and the slots left: $out"
  out=$(loop doctor 2>&1)
  grep -q "^ok: cores kept for you (the host file's reserveCores): cores $((n - 2)),$((n - 1)); card sessions and test runs run on cores 0[0-9,]*, and the test-slot pool has [0-9]* slots$" <<<"$out" \
    || fail "doctor does not name the kept cores and the slots left: $(grep -i 'cores' <<<"$out")"
}
