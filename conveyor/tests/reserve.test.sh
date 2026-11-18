#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: cores kept for the user (issue 196; the host file's reserveCores, lib/slots.sh slot_reserved, slot_keep,
# slot_reserve_why, slot_cpus, slot_keepwords): no test slot is on a kept core, no card session or test run runs on one,
# and doctor and health name the kept cores and the slots left, or why the machine cannot keep cores. Card sessions and
# test runs run at normal priority (issue 347: the host file's steer is gone).
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# The case's own host file, as the engine reads it, with <json> merged in.
reserve_host() { # <json>
  HOST=$XDG_CONFIG_HOME/conveyor/host.json
  mkdir -p "${HOST%/*}" && jq -n "$1" > "$HOST" || fail "the host file could not be written"
}
# The priority of process <pid>: "<nice> <ionice class>" (ionice's word for the class: idle, best-effort, none).
prio() { echo "$(ps -o ni= -p "$1" | tr -d ' ') $( { ionice -p "$1" 2>/dev/null || echo none; } | cut -d: -f1)"; } # <pid>
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

# Bugs it catches: a card session ran on the cores kept for the user; and (issue 347) a card session ran at lowered
# priority (nice 10, or taskpolicy's utility clamp), so card work crawled on a busy machine. The builder (an OpenCode
# session, through the words every session uses, slot_keepwords) runs on the cores left, at its caller's priority,
# with a host file that still sets the removed steer; with no cores kept its words are none.
t_reservesession() {
  # shellcheck disable=SC2034 # BUILD_TIMEOUT is read by builder()
  local d=$T/$CASE KEEP BUILD_TIMEOUT=30 n c
  command -v taskset >/dev/null || return 0
  n=$(nproc --all); [ "$n" -ge 3 ] || return 0
  mkdir -p "$d/bin" "$d/wt"
  # opencode stands in for every session's program: it writes the cores it may run on, and its priority, beside the worktree.
  printf '%s\n' '#!/usr/bin/env bash' 'taskset -cp $$ > "$PWD.cpus"; echo "$(ps -o ni= -p $$ | tr -d " ") $( { ionice -p $$ 2>/dev/null || echo none; } | cut -d: -f1)" > "$PWD.prio"; cat > /dev/null' \
    > "$d/bin/opencode"; chmod +x "$d/bin/opencode"
  eval "$(sed -n '/^builder() {/,/^}/p' "$SRC/lib/session.sh")"
  reserve_host '{reserveCores: 2, steer: true}'
  slot_keepwords
  ( PATH=$d/bin:$PATH; builder "$d/wt" prompt opencode:p/m '' '' opencode ) || fail "the builder did not run: $(cat "$d/wt.err" 2>&1)"
  c=$(sed 's/.*: //' "$d/wt.cpus") && [ -n "$c" ] || fail "the session did not say its cores"
  [ "$c" = "$(slot_keep)" ] || [ "$c" = "0-$((n - 3))" ] || fail "the session runs on cores $c, not those left (0-$((n - 3)))"
  [ "$(cat "$d/wt.prio")" = "$(prio $$)" ] || fail "the session ran at priority $(cat "$d/wt.prio"), not its caller's $(prio $$)"
  reserve_host '{steer: true}'
  slot_keepwords; [ ${#KEEP[@]} = 0 ] || fail "with no cores kept a session or test run is still started behind: ${KEEP[*]}"
}

# Bugs it catches: a card test run ran on the cores kept for the user; and (issue 347) it ran at idle CPU and disk
# priority (a steer slice, ionice's idle class, nice 19 or taskpolicy -b), so card tests crawled on a busy machine.
# The card's test command, run as a card's test step runs it (testonce), with no slot core to pin to, runs on the
# cores left at its caller's priority, with a host file that still sets the removed steer.
t_reservetestrun() {
  local w=$T/$CASE/wt out n
  command -v taskset >/dev/null || return 0
  n=$(nproc --all); [ "$n" -ge 3 ] || return 0
  setup '[]'; git -C "$R" worktree add -q --detach "$w" && mkdir -p "$w.testlog" || fail "the worktree"
  reserve_host '{reserveCores: 2, steer: true}'
  # shellcheck disable=SC2034 # LIVE and STUCK are read by watch(), which testonce() runs; names() is not run here
  # SLOT_CPUS emptied: this runner's own slot pool would else stand for the card's (no slot core to pin to, here).
  out=$( ( LIVE=0.2 STUCK=1200; export CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards SLOT_HOME=$T/$CASE/slot; cd "$R" && . "$SRC/conveyor.sh" state-dir > /dev/null \
    && eval "$(grep '^\. "\$HERE/lib/' "$SRC/commands/serve.sh")" && reportask "$w" && SLOT_CPUS='' \
    && testonce "$w" 'taskset -cp $$ > "$PWD.cpus"; echo "$(ps -o ni= -p $$ | tr -d " ") $( { ionice -p $$ 2>/dev/null || echo none; } | cut -d: -f1)" > "$PWD.prio"' ) 2>&1 ) \
    || fail "the run failed: $out $(cat "$w.test" 2>/dev/null)"
  [ "$(sed 's/.*: //' "$w.cpus")" = "0-$((n - 3))" ] || fail "the card's test command ran on cores $(cat "$w.cpus"), not those left (0-$((n - 3)))"
  [ "$(cat "$w.prio")" = "$(prio $$)" ] || fail "the card's test command ran at priority $(cat "$w.prio"), not its caller's $(prio $$)"
}

# Bug it catches: on a machine that cannot keep a process off a core (macOS: no taskset) the setting read as in
# force. There no core is kept, the words of a session name no taskset (nor any lowering), and slot_reserve_why says why.
t_reservemac() {
  local d=$T/$CASE KEEP t out
  mkdir -p "$d/bin"
  for t in jq nproc bash; do ln -s "$(command -v "$t")" "$d/bin/$t" || fail "no $t"; done
  reserve_host '{reserveCores: 2, steer: true}'
  out=$(PATH=$d/bin OSTYPE=darwin23; slot_reserve_why; echo "kept:$(slot_reserved)"; slot_keep && echo keep; slot_keepwords; echo "words:${KEEP[*]}")
  [ "$out" = $'macOS lets no program keep a process off a core\nkept:\nwords:' ] || fail "on macOS the setting is not shown as not available, or a core is kept: $out"
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
