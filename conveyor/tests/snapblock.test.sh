#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: the snapshot of a card blocked after it landed, and the snapshot's use of the records' lock.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# Bug: a card that landed, was then blocked by a loop restart ("its process ended without a result"), and still
# pushed and had its issue closed stays in Needs you as blocked, in the snapshot and in health (the host's view of the
# loop's problems): a done card shown as needing the owner. A card blocked after it landed with no later step of its
# own is still blocked. Record order decides, not time: c16's push started before its block and is written after it.
t_unblock() { local -x FILEMODE=1
  export TZ=UTC; setup '[]'; S=$ST; mkdir -p "$S"; d=$(date -u +%F)
  echo x > "$R/n.txt"; git -C "$R" add -A; git -C "$R" commit -qm next; sha=$(git -C "$R" rev-parse HEAD); git -C "$R" push -q origin main
  rec() { # <card> <issue> <minute> <step> <result> [extra json]
    jq -cn --arg c "$1" --argjson i "$2" --arg t "${d}T00:$3:00Z" --arg s "$4" --arg r "$5" --argjson x "${6:-{\}}" \
      '{card:$c,issue:$i,step:$s,time:$t,tokens:{claude:0,codex:0},result:$r,sha:"",reason:""} * $x' >> "$S/cards.jsonl"
  }
  for c in c14:14 c15:15 c16:16; do rec "${c%:*}" "${c#*:}" 00 picked ok '{"title":"T"}'; rec "${c%:*}" "${c#*:}" 01 review GO; done
  rec c14 14 02 landed ok "{\"sha\":\"$sha\",\"product\":false}"
  rec c14 14 03 blocked blocked '{"reason":"its process ended without a result"}'
  rec c14 14 04 pushed ok "{\"sha\":\"$sha\",\"sec\":1,\"head\":\"$sha\"}"; rec c14 14 05 issue ok
  rec c15 15 02 landed ok "{\"sha\":\"$sha\",\"product\":false}"
  rec c15 15 03 blocked blocked '{"reason":"its process ended without a result"}'
  rec c16 16 02 landed ok "{\"sha\":\"$sha\",\"product\":false}"
  rec c16 16 05 blocked blocked '{"reason":"its process ended without a result"}'
  rec c16 16 04 pushed ok "{\"sha\":\"$sha\",\"sec\":1,\"head\":\"$sha\"}"
  out=$(loop snapshot --fresh) || fail "snapshot exited non-zero"
  [ "$(jq -c '[.needsYou.blocked[].card]' <<<"$out")" = '["c15"]' ] \
    || fail "a card that pushed after it was blocked is in Needs you, or one blocked after it landed is not: $(jq -c '.needsYou.blocked' <<<"$out")"
  [ "$(jq -c '[.landed[] | select(.card == "c14" or .card == "c16") | [.step, .pushed]]' <<<"$out")" = '[["landed",true],["landed",true]]' ] \
    || fail "the card that pushed after it was blocked does not show as landed and pushed: $(jq -c '.landed' <<<"$out")"
  [ "$(jq -c '[.health.blocked[].card]' <<<"$out")" = '["c15"]' ] && [ "$(loop health | jq -c '[.blocked[].card]')" = '["c15"]' ] \
    || fail "health lists the card that pushed after it was blocked: $(loop health | jq -c .blocked)"
}

# Bug: every snapshot waits for the records' lock. On a busy host the loop's cards hold that lock for seconds at a
# time (a card waiting on a same-file card asks under it at every poll), so the wait was 3 to 7 s of a 20 to 40 s
# snapshot, and every reader of it timed out. Or, not waiting for it, the snapshot no longer holds a new issue before
# its copy, no longer dates the issues it lists, or reads a card `retry` moved from both files.
t_snaplock() { local -x FILEMODE=1
  setup "[$(issue 5 2026-03-01 P2)]"
  # Every flock on the card records is noted: the stub stands before the real one, which it then runs.
  real=$(command -v flock)
  # And the snapshot the retry below sets off says, when it comes to the lock of its copy, that it has to wait for it.
  { printf '#!/usr/bin/env bash\nreal=%q\n' "$real"; cat <<'EOF'; } > "$STUB/flock"; chmod +x "$STUB/flock"
[ ! /dev/fd/9 -ef "$ST/cards.jsonl" ] || echo "$*" >> "$STUB/locks"
if [ -e "$STUB/racing" ] && [ /dev/fd/5 -ef "$ST/cards.jsonl.checked.lock" ]; then rm -f "$STUB/racing"; "$real" -n 5 || echo waits > "$STUB/race"; fi
exec "$real" "$@"
EOF
  loop control start held >/dev/null 2>&1 || fail "start held was refused"
  jq -c ". + [$(issue 6 2026-03-02 P2)]" "$STUB/issues.json" > "$STUB/i" && mv "$STUB/i" "$STUB/issues.json"
  on() { local t=$1; shift; CONVEYOR_NOW=$(date -u -d "$t" +%s) loop "$@"; }
  # A new issue to hold is the one thing a snapshot takes the lock for, once: #6, new under Held, is held before the copy.
  : > "$STUB/locks"; out=$(on 2026-10-01 snapshot --fresh) || fail "snapshot exited non-zero"
  [ "$(wc -l < "$STUB/locks")" -eq 1 ] || fail "the snapshot that holds a new issue took the records' lock $(wc -l < "$STUB/locks") times, not once: $(tr '\n' ' ' < "$STUB/locks")"
  [ "$(jq -c '[.control.held, (.queue.order | map(.issue)), (.queue.holding | map(.issue)), ([.queue.order[], .queue.holding[]] | all(.since != null))]' <<<"$out")" = '[[6],[5],[6],true]' ] \
    || fail "the snapshot does not hold the new issue and date both: $(jq -c '[.control.held, .queue]' <<<"$out")"
  # A hold dates its issue in moved.json under that file's own lock, and the next snapshot shows that time.
  on 2026-11-01 control hold 5 >/dev/null 2>&1 || fail "control hold was refused"
  # With no new issue to hold, the snapshot never waits for the lock.
  : > "$STUB/locks"; out=$(on 2026-11-05 snapshot --fresh) || fail "snapshot exited non-zero"
  [ ! -s "$STUB/locks" ] || fail "a snapshot with no new issue to hold took the records' lock: $(tr '\n' ' ' < "$STUB/locks")"
  [ "$(jq -c '.queue.holding | map([.issue, .since])' <<<"$out")" = '[[5,"2026-11-01T00:00:00Z"],[6,"2026-10-01T00:00:00Z"]]' ] \
    || fail "a hold's time is not the snapshot's since: $(jq -c .queue.holding <<<"$out")"
  # A snapshot that begins while `retry` has a card's lines in both files (appended to the retried file, the records
  # not yet rewritten) waits for the rewrite: the stub of python3 starts one when the state helper is asked to rewrite
  # the records, and lets the rewrite go on only when the snapshot waits for the lock of its copy (waits) or has ended
  # without waiting (done).
  line() { printf '{"card":"c1","issue":5,"step":"%s","time":"%s","tokens":{"claude":0,"codex":0},"result":"%s","sha":"","reason":"%s","repo":"r"}\n' "$@"; }
  line picked 2026-11-06T00:00:00Z ok '' >> "$ST/cards.jsonl"; line blocked 2026-11-06T00:10:00Z blocked 'build: failed' >> "$ST/cards.jsonl"
  { printf '#!/usr/bin/env bash\nreal=%q; snap() { CONVEYOR_MAIN=%q CONVEYOR_CARDS=%q bash %q snapshot --fresh; }\n' "$(command -v python3)" "$R" "$T/$CASE/cards" "$SRC/conveyor.sh"; cat <<'EOF'; } > "$STUB/python3"; chmod +x "$STUB/python3"
if [[ " $* " == *' rewrite cards '* ]] && [ -p "$STUB/race" ]; then
  : > "$STUB/racing"; ( snap > "$STUB/mid" 2>/dev/null; echo done > "$STUB/race" ) 5>&- 9>&- > /dev/null &
  read -r w < "$STUB/race"; echo "$w" > "$STUB/raced"
fi
exec "$real" "$@"
EOF
  mkfifo "$STUB/race"; loop retry 5 >/dev/null 2>&1 || fail "retry was refused"
  [ "$(cat "$STUB/raced" 2>/dev/null)" = waits ] || fail "a snapshot begun while retry had the card's lines in both files did not wait for the rewrite: it shows $(jq -c '[(.needsYou.blocked | map(.card)), .metrics.prev.cards]' "$STUB/mid" 2>/dev/null)"
  read -r _ < "$STUB/race"; rm -f "$STUB/race" "$STUB/python3"
  # What it then shows is the card after the retry: moved, once, and no longer waiting on the owner.
  [ "$(jq -c '[.needsYou.blocked, .metrics.prev.cards]' "$STUB/mid")" = '[[],1]' ] || fail "the snapshot that waited does not show the retried card moved, once: $(jq -c '[.needsYou.blocked, .metrics.prev.cards]' "$STUB/mid")"
}
