#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: the snapshot of a card blocked after it landed, the snapshot's use of the records' lock, and the
# Foreman's notes on blocked cards in it.
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
t_unblock() {
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
t_snaplock() {
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
  # The card ran 10 days ago, in the snapshot's prev week (13 to 7 days before today) in any time zone: the snapshot
  # below runs on the real clock, so a fixed date leaves that week as the days pass and prev counts no card.
  ago=$(date -u -d '10 days ago' +%F)
  line picked "${ago}T12:00:00Z" ok '' >> "$ST/cards.jsonl"; line blocked "${ago}T12:10:00Z" blocked 'build: failed' >> "$ST/cards.jsonl"
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

# Issue 1685: the Foreman's notes on blocked cards, kept by `conveyor.sh foreman note` (commands/foreman-note.sh) in
# the record's state folder, where the snapshot is printed, so a Foreman on another machine (it runs the command by its
# ask, over ssh) has them shown too. snapprint gives a note as foreman {note, ask, since} on a card of needsYou.blocked,
# and on one of recordsNow's blocked (c18, blocked after the kept snapshot's build began), which then joins
# needsYou.blocked. Bugs it catches: a note kept for a card that is not blocked (c19, only picked) or that waits for
# the owner's yes (c21); a note shown on a card blocked again after it (c16: its note is of
# an earlier block), after the card was retried, after a renewal by another session (the role moved), or once its
# last renewal is older than NOTELEASE (the Foreman's session gone: nothing renews it), and again once that session
# renews or writes a note later; a card blocked after the build shown with no note; a notes line over 128 KiB; the
# notes of cards no longer blocked kept.
t_foremannote() {
  # The records are dated yesterday: a note is dated now, and one written before 00:01 UTC would else be older than
  # the 00:01 blocks below, so the snapshot would rightly drop it as a note of an earlier block.
  setup "[$(issue 15 2026-11-01 P2), $(issue 16 2026-11-01 P2), $(issue 17 2026-11-01 P2), $(issue 18 2026-11-01 P2), $(issue 19 2026-11-01 P2)]"; d=$(TZ=UTC p_date yesterday +%F)
  c() { echo "c20261101T000000-alpha-$1"; } # <issue>: its card's ID
  rec() { # <issue> <minute> <step> <result> [extra json]
    jq -cn --arg c "$(c "$1")" --argjson i "$1" --arg t "${d}T00:$2:00Z" --arg s "$3" --arg r "$4" --argjson x "${5:-{\}}" \
      '{card:$c,issue:$i,step:$s,time:$t,tokens:{claude:0,codex:0},result:$r,sha:"",reason:""} * $x' >> "$ST/cards.jsonl"
  }
  for i in 15 16 17 18 19; do rec "$i" 00 picked ok '{"title":"T"}'; done
  for i in 15 16 17; do rec "$i" 01 blocked blocked '{"reason":"the session made no change"}'; done
  # c21 stopped for the owner's yes to a lint policy change (block(), lib/card.sh): the views list it as waiting.
  rec 21 00 picked ok '{"title":"T"}'; rec 21 01 blocked blocked '{"reason":"lint policy: needs Dana'"'"'s yes: it changes lint policy: .lintrc"}'
  loop snapshot --fresh > /dev/null || fail "snapshot --fresh exited non-zero"
  note() { loop foreman note sess-1 "$(c "$1")" "${@:2}"; } # <issue> --does | --ask <text>
  for a in "15 --does hand run in progress" "16 --does an earlier block" "17 --ask which fix to land"; do
    read -r i k t <<<"$a"; out=$(note "$i" "$k" "$t" 2>&1) || fail "foreman note sess-1 $(c "$i") $k '$t' was refused: $out"
  done
  before=$(cat "$ST/foreman-notes")
  out=$(note 19 --does 'not blocked' 2>&1); [ $? = 3 ] || fail "foreman note sess-1 $(c 19) --does 'not blocked', a card only picked, did not end 3: $out"
  # A card the records have no line of ends 4, apart from one not blocked: the Foreman then asks its next project with
  # the same tag (foreman/note.sh). Bug it catches: both ended 3, so the Foreman stopped at the first such project.
  out=$(note 20 --does 'no such card' 2>&1); [ $? = 4 ] || fail "foreman note sess-1 $(c 20) --does 'no such card', a card with no record line, did not end 4: $out"
  # c21 waits for the owner's yes, where no view shows a note (snapprint gives notes on blocked cards only). Bug it
  # catches: its note was kept and the command said it showed.
  out=$(note 21 --does 'asked the owner' 2>&1); rc=$?
  [ "$rc" = 3 ] && [[ $out == *"waits for the owner's yes"* ]] || fail "foreman note sess-1 $(c 21) --does 'asked the owner', a card waiting for the owner's yes, ended $rc: $out"
  [ "$(cat "$ST/foreman-notes")" = "$before" ] || fail "foreman note sess-1 on $(c 19) (only picked), $(c 20) (no line) and $(c 21) (waits for a yes) changed foreman-notes: $(cat "$ST/foreman-notes")"
  # c16's note dates from before its block: blocked again since, the note is of an earlier block.
  { head -n 1 "$ST/foreman-notes"; sed -n 2p "$ST/foreman-notes" | jq -c --arg k "$(c 16)" --arg d "$d" '.[$k].since = "\($d)T00:00:30Z"'; } > "$ST/n" && mv "$ST/n" "$ST/foreman-notes"
  # notes [<snapshot>]: {<card>: "<note>|<ask>|<since is a time>", or null with no note} for each blocked card of the
  # kept snapshot and of recordsNow. A plain read can start a build in the background, after which recordsNow is gone
  # and the kept snapshot holds the cards it held: the two lists together say the same either way, but for a retried
  # card (c15, below): the kept needsYou.blocked holds it, with no note, until a build that began after the retry.
  notes() { jq -cS '[(.needsYou.blocked[], (.recordsNow.blocked // [])[]) | {(.card | sub(".*-"; "c")): (.foreman | if . then "\(.note)|\(.ask)|\(.since | test("^\\d{4}-\\d\\d-\\d\\dT\\d\\d:\\d\\d:\\d\\dZ$"))" else null end)}] | add' <<<"${1:-$(loop snapshot)}"; }
  # The records not changed since the build (no recordsNow): the notes are on the kept snapshot's needsYou.blocked.
  snap=$(loop snapshot); out=$(notes "$snap")
  [ "$(jq -c .recordsNow <<<"$snap")" = null ] && [ "$out" = '{"c15":"hand run in progress|false|true","c16":null,"c17":"which fix to land|true|true"}' ] \
    || fail "with foreman-notes $(tr '\n' ' ' < "$ST/foreman-notes"), the kept snapshot's notes on c15, c16 (blocked after its note) and c17 (--ask) are: $out (recordsNow: $(jq -c .recordsNow <<<"$snap"))"
  # c18, blocked after the build, is in recordsNow's blocked, with its note.
  rec 18 02 blocked blocked '{"reason":"the session made no change"}'
  out=$(note 18 --does 'fix card filed' 2>&1) || fail "foreman note sess-1 $(c 18) --does 'fix card filed', blocked after the build, was refused: $out"
  # With the build held off (its lock held), the kept snapshot is the one built before c18 blocked: c18 joins its
  # needsYou.blocked, once, from the records (fromRecords), with its note. Bug it catches: c18 and its note only in
  # recordsNow, which /units and the Board's Needs you column do not read, so they showed it nowhere until the build.
  exec {lk}>>"$ST/snapshot.json.lock" && flock -w 120 "$lk" || fail "the kept lock could not be held"
  out=$(loop snapshot | jq -c --arg k "$(c 18)" '[.needsYou.blocked[] | select(.card == $k) | [.fromRecords, .foreman.note]]')
  exec {lk}>&-
  [ "$out" = '[[true,"fix card filed"]]' ] || fail "with c18 blocked after the build and noted, its entries in needsYou.blocked are $out"
  all='{"c15":"hand run in progress|false|true","c16":null,"c17":"which fix to land|true|true","c18":"fix card filed|false|true"}'
  out=$(notes); [ "$out" = "$all" ] || fail "with c18 blocked after the build and noted, the snapshot's notes are: $out"
  noteinretry # retry 15, with a note on c15 asked for while the retry holds the records' lock
  out=$(loop snapshot | jq -c '[(.needsYou.blocked[], (.recordsNow.blocked // [])[]) | select(.foreman != null) | .card | sub(".*-"; "c")] | unique')
  [ "$out" = '["c17","c18"]' ] || fail "after retry 15, the cards with a note are $out, not c17 and c18"
  # A notes line over 128 KiB (Linux's limit on one argument) still gives the notes, and the snapshot prints whole;
  # the next note keeps only the cards still blocked (c15, retried, and the 600 others are dropped). Bugs: the line
  # given to jq as an argument (the snapshot printed its first fields only, and the next note failed), and the notes of
  # cards no longer blocked kept for ever, so the line grows to that limit.
  { head -n 1 "$ST/foreman-notes"; sed -n 2p "$ST/foreman-notes" | jq -c '. + ([range(600)] | map({key: "c20261101T000000-alpha-\(. + 1000)", value: {note: ("x" * 250), ask: false, since: "2026-11-01T00:00:00Z"}}) | from_entries)'; } > "$ST/n" && mv "$ST/n" "$ST/foreman-notes"
  [ "$(sed -n 2p "$ST/foreman-notes" | wc -c)" -gt 131072 ] || fail "the notes line of the fixture is not over 128 KiB"
  out=$(loop snapshot | jq -c '[(.needsYou.blocked[], (.recordsNow.blocked // [])[]) | select(.foreman != null) | .card | sub(".*-"; "c")] | unique')
  [ "$out" = '["c17","c18"]' ] || fail "with a notes line of $(sed -n 2p "$ST/foreman-notes" | wc -c) bytes, the snapshot's cards with a note are: $out"
  # A note over 128 KiB on c18, blocked and with the records newer than the build: recordsNow carries it to the last jq
  # of the print. The build is held off (its lock held) and the records dated after it, so recordsNow is there to read.
  # Bug: recordsNow given to that jq as an argument, so it did not start and the snapshot printed its first fields only.
  { head -n 1 "$ST/foreman-notes"; sed -n 2p "$ST/foreman-notes" | jq -c --arg k "$(c 18)" '.[$k].note = ("y" * 140000)'; } > "$ST/n" && mv "$ST/n" "$ST/foreman-notes"
  exec {lk}>>"$ST/snapshot.json.lock" && flock -w 120 "$lk" && touch "$ST/cards.jsonl" || fail "the kept lock could not be held"
  out=$(loop snapshot | jq -c '[(.recordsNow.blocked // [])[] | select(.foreman != null) | {(.card | sub(".*-"; "c")): (.foreman.note | length)}] | add')
  exec {lk}>&-
  [ "$out" = '{"c17":17,"c18":140000}' ] || fail "with a note of 140000 characters on c18, recordsNow's notes (their lengths) are: $out"
  out=$(note 18 --does 'fix card filed' 2>&1) || fail "foreman note sess-1 $(c 18) --does 'fix card filed', with a notes line over 128 KiB, was refused: $out"
  out=$(sed -n 2p "$ST/foreman-notes" | jq -c 'keys | map(sub(".*-"; "c"))')
  [ "$out" = '["c16","c17","c18"]' ] || fail "after retry 15 and a note on c18, foreman-notes keeps the notes of $out, not only c16, c17 and c18 (still blocked)"
  # A notes line that is not JSON gives no note, and the snapshot still prints whole (bug: jq printed nothing).
  cp "$ST/foreman-notes" "$ST/good"; { head -n 1 "$ST/good"; echo 'not json'; } > "$ST/foreman-notes"
  out=$(loop snapshot | jq -c --arg k "$(c 17)" '[([.needsYou.blocked[] | select(.foreman != null)] | length), ([.needsYou.blocked[].card] | index($k) != null)]')
  [ "$out" = '[0,true]' ] || fail "with foreman-notes line 2 'not json', the snapshot's [cards with a note, c17 still blocked] are $out, not [0,true]"
  mv "$ST/good" "$ST/foreman-notes"
  loop foreman note sess-2 renew || fail "the renewal by sess-2 was refused"
  out=$(loop snapshot | jq -c '[(.needsYou.blocked[], (.recordsNow.blocked // [])[]) | select(.foreman != null) | .card]')
  [ "$out" = '[]' ] || fail "after a renewal by sess-2 (the role moved), the notes of sess-1 still show on $out"
  # The checks below name each blocked card of the snapshot, so the kept one must be built after retry 15. A plain
  # read prints the kept snapshot at once and waits for no build, and --fresh builds it here. Bug of the case: it read
  # on while the writer's build ran, and on a busy machine the kept snapshot still held c15 at the first check below.
  loop snapshot --fresh > /dev/null || fail "snapshot --fresh after retry 15 exited non-zero"
  # The Foreman's session gone: its watcher no longer renews the notes, and the last renewal is older than NOTELEASE
  # (300 s). The same session resumed later (conveyor.sh foreman resumes it) renews again, and writes a note: neither
  # brings the old notes back. Bug: the renewal set the time of the old notes anew, so they showed again.
  for a in "17 --ask which fix to land" "18 --does fix card filed"; do
    read -r i k t <<<"$a"; out=$(note "$i" "$k" "$t" 2>&1) || fail "foreman note sess-1 $(c "$i") $k '$t' was refused: $out"
  done
  expire() { { read -r s _ && printf '%s %s\n' "$s" $((EPOCHSECONDS - 301)) && cat; } < "$ST/foreman-notes" > "$ST/n" && mv "$ST/n" "$ST/foreman-notes"; }
  expire; out=$(notes); [ "$out" = '{"c16":null,"c17":null,"c18":null}' ] || fail "with the notes last renewed 301 s ago, they still show: $out"
  # Each is checked on notes ended, with nothing done between that drops them.
  out=$(note 18 --does 'hand run' 2>&1) || fail "foreman note sess-1 $(c 18) --does 'hand run' was refused: $out"
  out=$(notes); [ "$out" = '{"c16":null,"c17":null,"c18":"hand run|false|true"}' ] \
    || fail "a note on c18 by sess-1 after its notes ended (301 s) does not show c18's note alone: $out"
  expire; loop foreman note sess-1 renew || fail "the renewal by sess-1 was refused"
  out=$(notes); [ "$out" = '{"c16":null,"c17":null,"c18":null}' ] || fail "a renewal by sess-1 after its notes ended (301 s) shows them again: $out"
}

# t_foremannote's retry of c15 (still blocked, with a note), with a note on c15 asked for at once. What must stay true:
# a note is kept only for a card the records hold blocked as it is written. The other writer is retry, which takes the
# card's lines out under the records' lock: the note reads the records and writes under that lock too (locked noteput).
# retry is paused once it holds the lock, before it writes (its flock on the records, which flock() below wraps), and
# the note on c15 is started then: it waits at the lock (its own flock() marks that it reached it), and after the
# retry finds no line of c15 (exit 4), so foreman-notes is unchanged. Bug it catches: a note written outside the lock
# reads c15 still blocked while retry holds the lock, and keeps the note of a retried card. The note's run is polled
# until it waits at the lock or ends: whether it reads the records before the retry writes is what is checked, and
# only a real run of both shows that. Uses t_foremannote's c and note.
noteinretry() {
  local before h rp np rc
  # held: retry says it holds the lock (opened both ways here, so its write never waits); go: the case lets it on.
  before=$(cat "$ST/foreman-notes"); : > "$STUB/pause"; mkfifo "$STUB/go" "$STUB/held" && exec {h}<>"$STUB/held" || fail "the case could not make its pipes"
  atlock() { [ "$1" = 9 ] && [ /dev/fd/9 -ef "$ST/cards.jsonl" ]; } # flock's arguments: whether it is the records' lock
  ( flock() { command flock "$@" || return; atlock "$@" && rm "$STUB/pause" 2>/dev/null || return 0; echo > "$STUB/held"; read -r _ < "$STUB/go"; }
    export -f flock atlock; loop retry 15 > "$STUB/retry.out" 2>&1 ) & rp=$!
  read -r -t 120 -u "$h" _ || fail "retry 15 did not reach the records' lock: $(cat "$STUB/retry.out")"
  ( flock() { ! atlock "$@" || : > "$STUB/atlock"; command flock "$@"; }
    export -f flock atlock; note 15 --does 'hand land' > "$STUB/note.out" 2>&1 ) & np=$!
  wait_until "[ -e \"$STUB/atlock\" ] || ! kill -0 $np 2>/dev/null" || fail "the note on c15 neither reached the records' lock nor ended"
  echo > "$STUB/go"; exec {h}>&-
  wait "$rp" || fail "retry 15 was refused: $(cat "$STUB/retry.out")"
  wait "$np"; rc=$?
  [ "$rc" = 4 ] && [ "$(cat "$ST/foreman-notes")" = "$before" ] \
    || fail "foreman note sess-1 $(c 15) --does 'hand land', run while retry 15 held the records' lock, ended $rc ($(cat "$STUB/note.out")) and left foreman-notes: $(cat "$ST/foreman-notes")"
}
