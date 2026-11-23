#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: the push step's test slot (lib/push.sh pushone, lib/slots.sh slot_first): a push takes the next free
# slot of the machine's pool ahead of the test units that wait for one, and runs its pre-push hook in the loop's own cgroup.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# Issue 581 (the owner, 2026-11-15: pushes ran outside the slot pool, beside every card's test units, and on a machine
# at load 97 their pre-push checks were killed at their 600 s limit, so cards that had landed could not push).
# Bugs it catches: a push that runs its hook with every slot held, outside the pool (the hook runs before a slot is
# given back); a push that waits in the pool as one more waiter, so a test unit that waited takes the slot given back
# first (it holds the push's place; this one is a race without the fix, so it fails often, not always); and (issue 348)
# a hook started in a systemd scope of its own with a hard memory cap (slot_box), not in the loop's cgroup (Linux).
# A pool of 2, both slots held; two test units wait for a slot as a card's test step does (tests(): slot_try, then
# slot_wait); the loop's push() pushes main. Slot 1 is given back: the push's hook runs first, and the units still wait.
t_pushslot() {
  local d=$T/$CASE/run P=$T/$CASE/slots u sha hook
  export XDG_CONFIG_HOME=$T/$CASE/config
  mkdir -p "$d" "$XDG_CONFIG_HOME/conveyor" && echo "{\"testSlots\": 2, \"testSlotsDir\": \"$P\"}" > "$XDG_CONFIG_HOME/conveyor/host.json"
  setup '[]'
  # The hook says the cgroup it ran in and that it ran, then holds its slot until the case ends it.
  hook='#!/usr/bin/env bash\ncat /proc/self/cgroup > %q/hookcg 2>/dev/null\necho push >> %q/order\nuntil [ -e %q/end ]; do sleep 0.05; done\n' # sleep: the hook's poll for its end
  printf "$hook" "$d" "$d" "$d" > "$R/.git/hooks/pre-push" && chmod +x "$R/.git/hooks/pre-push"
  mkdir -p "$P"; : >> "$P/1"; : >> "$P/2"
  for u in 1 2; do flock "$P/$u" bash -c 'until [ -e "$0" ]; do sleep 0.05; done' "$d/free$u" & done
  wait_until '! flock -n "$P/1" true && ! flock -n "$P/2" true' || fail "the two slots were not held"
  for u in 1 2; do
    ( . "$SRC/lib/slots.sh"; slot_pool || exit 1; : > "$d/waits$u"
      until slot_try || slot_wait; do :; done
      echo unit >> "$d/order"; until [ -e "$d/end" ]; do sleep 0.05; done ) &
  done
  wait_until '[ -e "$d/waits1" ] && [ -e "$d/waits2" ]' || fail "the test units did not start waiting"
  echo x > "$R/n.txt"; git -C "$R" add -A; git -C "$R" commit -qm next; sha=$(git -C "$R" rev-parse HEAD)
  # The loop's shell, as `conveyor.sh run` starts it (conveyor.sh's own engine files, then the ones commands/run.sh
  # loads): holding no slot.
  # shellcheck disable=SC2034 # HERE is read by the lines of conveyor.sh and commands/run.sh run by the eval
  ( HERE=$SRC; export CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards; unset CONVEYOR_TEST_SLOT
    eval "$(sed -n '/^\. "\$HERE\/lib\/portable.sh"/,/^\. "\$HERE\/lib\/records.sh"/p' "$SRC/conveyor.sh")"
    eval "$(grep '^\. "\$HERE/lib/' "$SRC/commands/run.sh")"
    names || exit 1; push c1-1 1 ) > "$d/push.out" 2>&1 &
  wait_until 'compgen -G "$P/first/[0-9]*" >/dev/null' "cat '$d/push.out'" || fail "the push did not wait for a test slot"
  # Review of issue 1078: the views said the pre-push hook ran while the push still waited for its test slot.
  [ "$(jq -r .stage "$ST/pushing")" = ready ] || fail "a push that waits for a test slot does not say so: $(cat "$ST/pushing")"
  [ ! -e "$d/order" ] || fail "something ran with every slot held: $(cat "$d/order")"
  : > "$d/free1"
  wait_until '[ -s "$d/order" ]' "cat '$d/push.out'" || fail "nothing took the slot given back"
  [ "$(jq -r .stage "$ST/pushing")" = hook ] || fail "a push whose hook runs does not say so: $(cat "$ST/pushing")"
  [ "$(cat "$d/order")" = push ] || fail "a waiting test unit took the slot given back before the push, or with it: $(cat "$d/order")"
  [ ! -r /proc/self/cgroup ] || [ "$(cat "$d/hookcg")" = "$(cat /proc/self/cgroup)" ] \
    || fail "the push's hook ran in a cgroup of its own (a capped box), not the loop's: $(cat "$d/hookcg")"
  : > "$d/end"; : > "$d/free2"
  wait_until "[ \"\$(git -C '$T/$CASE/origin' rev-parse main 2>/dev/null)\" = $sha ]" "cat '$d/push.out'" || fail "the push did not reach origin"
  wait_until '[ "$(wc -l < "$d/order")" = 3 ]' || fail "the waiting units did not take the slots once they came free: $(cat "$d/order")"
  wait
}

# Review of #1432. Bug it catches: a push read the machine's load (loadfactor()) before it waited for a test slot
# (slot_first), and ran its pre-push hook with that factor and time limit, though the load had changed during the wait.
# A pool of 1, its slot held; the push waits at load 0 (factor 1), the load goes to 2 per core, then the slot is given
# back. With pushTimeout 2 the hook must get the factor 2 and its scaled 4 s: it lives past 3 s (not cut at the 2 s read
# before the wait), is cut before it ends at 4.5 s (a limit of 5 s or more lets it end and the push land), and the push
# line's reason names the 4 s limit the hook ran under (the limit the subshell hands back in $wt.limit), not 2 s.
t_pushslotload() {
  local d=$T/$CASE/run P=$T/$CASE/slots sha hook
  export XDG_CONFIG_HOME=$T/$CASE/config
  mkdir -p "$d" "$XDG_CONFIG_HOME/conveyor" && echo "{\"testSlots\": 1, \"testSlotsDir\": \"$P\"}" > "$XDG_CONFIG_HOME/conveyor/host.json"
  setup '[]'; tune '.tunables.pushTimeout = 2' || fail "the pack"
  hook='#!/usr/bin/env bash\nprintf %%s "${CONVEYOR_LOAD_FACTOR-unset}" > %q/hookfactor\nsleep 3\n: > %q/past3\nsleep 1.5\n' # sleep: past pushTimeout 2, then past its scaled 4 s
  printf "$hook" "$d" "$d" > "$R/.git/hooks/pre-push" && chmod +x "$R/.git/hooks/pre-push" || fail "the hook could not be written"
  mkdir -p "$P"; : >> "$P/1"; echo 0 > "$d/load"
  flock "$P/1" bash -c 'until [ -e "$0" ]; do sleep 0.05; done' "$d/free1" &
  wait_until '! flock -n "$P/1" true' || fail "the slot was not held"
  echo x > "$R/n.txt"; git -C "$R" add -A; git -C "$R" commit -qm next; sha=$(git -C "$R" rev-parse HEAD)
  # The loop's shell, as in t_pushslot, with the machine's load (p_load) read from $d/load.
  # shellcheck disable=SC2034 # HERE is read by the lines of conveyor.sh and commands/run.sh run by the eval
  ( HERE=$SRC; export CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards; unset CONVEYOR_TEST_SLOT CONVEYOR_LOAD_FACTOR
    eval "$(sed -n '/^\. "\$HERE\/lib\/portable.sh"/,/^\. "\$HERE\/lib\/records.sh"/p' "$SRC/conveyor.sh")"
    eval "$(grep '^\. "\$HERE/lib/' "$SRC/commands/run.sh")"
    p_load() { cat "$d/load"; }
    names || exit 1; push c1-1 1 ) > "$d/push.out" 2>&1 &
  wait_until 'compgen -G "$P/first/[0-9]*" >/dev/null' "cat '$d/push.out'" || fail "the push did not wait for a test slot"
  echo "$((2 * $(nproc --all)))" > "$d/load"; : > "$d/free1"
  wait
  [ "$(cat "$d/hookfactor" 2>&1)" = 2 ] && [ -e "$d/past3" ] || fail "the load went from 0 to 2 per core while the push waited for its slot: its hook was cut at the 2 s limit read before the wait, or not given the factor 2: $(cat "$d/hookfactor" "$d/push.out" 2>&1 | tail -n 5)"
  [ "$(git -C "$T/$CASE/origin" rev-parse main 2>/dev/null)" != "$sha" ] || fail "the 4.5 s hook ran to its end and the push landed: its limit was over the scaled 4 s"
  st 'select(.step == "push" and .result == "fail") | .reason' | grep -qF 'exit 124 (124 is the 4s timeout)' \
    || fail "the push line does not say the push was cut at the scaled 4 s limit: $(st 'select(.step == "push")' | tail -c 600)"
}
