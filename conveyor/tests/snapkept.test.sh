#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases: the kept snapshot (commands/snapshot.sh): readers print it at once, one writer rebuilds it, and the
# rebuild reads only the record lines past the kept summaries (#398).
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# A line of the records: <card> <issue> <step> <result> <minute of 2026-11-17T10> [extra json]. Its repo is
# snapkept_old, which no summary keeps, so a program that reads the line itself can be told from one that reads a
# summary. Every case file is sourced into one shell (conveyor.test.sh), so the helpers carry the file's name.
snapkept_line() {
  jq -cn --arg c "$1" --argjson i "$2" --arg s "$3" --arg r "$4" --arg t "2026-11-17T10:$5:00Z" --argjson x "${6:-{\}}" \
    '{card: $c, issue: $i, step: $s, time: $t, tokens: {claude: 1, codex: 0}, result: $r, sha: "", reason: "", repo: "snapkept_old"} * $x'
}
# Two issues with cards (one landed with a follow-up, one at its review with a finding the judge declined), a
# retried card and a main-red card, then one snapshot built and kept: the fixture of every case.
snapkept_setup() {
  setup "[$(issue 1 2026-11-01),$(issue 2 2026-11-02),$(issue 3 2026-11-03)]"; mkdir -p "$ST" "$T/$CASE/bin" "$T/$CASE/tmp"
  {
    snapkept_line c1 1 picked ok 00 '{"title": "one"}'
    snapkept_line c1 1 landed ok 01 '{"sha": "abc", "product": false, "followups": [3]}'
    snapkept_line c2 2 picked ok 02 '{"title": "two"}'
    snapkept_line c2 2 review NO-GO 03 '{"judge": {"accepted": [{"n": 1, "finding": "P1 kept"}], "declined": [{"n": 2, "finding": "P2 not so"}]}}'
    snapkept_line c3 0 picked ok 04 '{"mainRed": "abcdef0123456789", "title": "red"}'
  } > "$ST/cards.jsonl"
  { snapkept_line c0 2 picked ok 00 '{"title": "two"}'; snapkept_line c0 2 blocked blocked 01 '{"reason": "brief: failed"}'; } > "$ST/retried.jsonl"
  echo '{"by": "judge", "card": "c2", "issue": 2, "finding": "P2 not so", "time": "2026-11-17T10:05:00Z"}' > "$ST/declined.jsonl"
  loop snapshot --fresh > /dev/null || fail "the first snapshot exited non-zero"
  [ -s "$ST/snapshot.json" ] || fail "the first snapshot was not kept: $(ls "$ST")"
}
# A new record line, of a card no earlier line names.
snapkept_new() { snapkept_line c9 3 picked ok 06 '{"title": "three", "repo": "new"}' >> "$ST/cards.jsonl"; }
# A python3 on PATH that runs <shell> before the real one when it runs cardruns.py (once a build).
snapkept_py() { # <shell>
  printf '#!/usr/bin/env bash\n[[ $* != *cardruns.py* ]] || { %s; }\nexec %q "$@"\n' "$1" "$(command -v python3)" > "$T/$CASE/bin/python3" && chmod +x "$T/$CASE/bin/python3"
}
# A jq on PATH that counts the record lines from before the new one (snapkept_old) in each file and pipe it is given
# and in its stdin when that is a pipe or a file (each read once into a copy it reads instead), and notes each run
# that read one in <log>: how many, and its first arguments.
snapkept_jq() { # <log>
  cat > "$T/$CASE/bin/jq" <<EOF || fail "the shim could not be written"
#!/usr/bin/env bash
n=0 args=()
for a in "\$@"; do
  if [ -p "\$a" ] || { [ -f "\$a" ] && [[ \$a != *.jq ]]; }; then c=\$(mktemp '$T/$CASE/tmp/a.XXXXXX'); cat -- "\$a" > "\$c"; n=\$((n + \$(grep -c snapkept_old "\$c"))); a=\$c; fi
  args+=("\$a")
done
if [ -p /dev/stdin ] || [ -f /dev/stdin ]; then s=\$(mktemp '$T/$CASE/tmp/s.XXXXXX'); cat > "\$s"; n=\$((n + \$(grep -c snapkept_old "\$s"))); exec < "\$s"; fi
[ "\$n" = 0 ] || echo "\$n \${args[*]:0:3}" | cut -c1-200 >> '$1'
exec $(command -v jq) "\${args[@]}"
EOF
  chmod +x "$T/$CASE/bin/jq"
}
# Every input of the kept snapshot dated in 2000, and the kept snapshot itself <s> seconds old: none changed since.
# Its build-start file (snapshot.json.at) is dated the same, as a build that ended leaves it (snapkept_building).
# GitHub's answers (snapgh/at) too: asked after the kept snapshot's build began, they are taken for a build to come.
# Its build counted each card's lines of the records as they are now (snapshot.json.records, snapkeep): a line a case
# wrote into them before this is one the kept snapshot holds.
snapkept_quiet() { # <s>
  local t; printf -v t '%(%Y%m%d%H%M.%S)T' $(($(date +%s) - $1))
  touch -c -t 200001010000 "$ST/cards.jsonl" "$ST/retried.jsonl" "$ST/control.json" "$ST/snapgh/at" && mkdir -p "$T/$CASE/cards" && touch -t 200001010000 "$T/$CASE/cards" \
    && touch -t "$t" "$ST/snapshot.json" "$ST/snapshot.json.at" \
    && jq -r .card "$ST/cards.jsonl" | sort | uniq -c | awk '{ print $1 "\t" $2 }' > "$ST/snapshot.json.records" || fail "the fixture's times could not be set"
}
# Waits until no build is under way and the kept snapshot shows c9. A build is under way from the time it dates
# snapshot.json.at (snapkeep) to the rename that dates the kept snapshot the same. Bug (#1242): this wait took the
# kept lock to see that no writer held it, and a writer that found the lock taken by the wait ended unbuilt (it takes
# any holder for a writer that builds next), so no snapshot with c9 came under load. No look takes the lock.
snapkept_building() { [ "$ST/snapshot.json.at" -nt "$ST/snapshot.json" ]; }
snapkept_built() {
  for _ in $(seq 100); do
    ! snapkept_building && jq -e '.belt | map(.card) | index("c9")' "$ST/snapshot.json" > /dev/null 2>&1 && return 0
    sleep 0.2
  done
  fail "no writer put a snapshot with c9 in place in 20 s: $(jq -c '[.belt[].card]' "$ST/snapshot.json" 2>&1)"
}
snapkept_ino() { ls -i "$ST/snapshot.json" | awk '{print $1}'; }

# Bug: every reader (the Board, /units, each watcher) built its own snapshot, a minute of jq on a long history, and
# gave up waiting before it ended. With a kept snapshot whose inputs did not change, the reader prints it, with its
# age first, and no jq it runs reads a line of the records (the jq shim counts them).
t_snapkeptread() {
  local log=$T/$CASE/old.lines out at
  snapkept_setup; snapkept_quiet 20; snapkept_jq "$log"
  out=$(PATH=$T/$CASE/bin:$PATH loop snapshot < /dev/null) || fail "the reader exited non-zero"
  [ ! -s "$log" ] || fail "the reader ran jq on the records: $(head -n 5 "$log")"
  printf -v at '%(%s)T' -1
  jq -e --argjson now "$at" '.snapshotAge >= 20 and .snapshotAge <= 25 and (.snapshotAt | fromdate) >= $now - .snapshotAge - 1' <<<"$out" > /dev/null \
    || fail "the reader did not say the kept snapshot's age (20 s): $(jq -c '{snapshotAt, snapshotAge}' <<<"$out" 2>&1)"
  [ "$(jq -cS 'del(.snapshotAt, .snapshotAge, .recordsNewer)' <<<"$out")" = "$(jq -cS . "$ST/snapshot.json")" ] || fail "the reader did not print the kept snapshot"
  [ "$(jq .recordsNewer <<<"$out")" = false ] || fail "the reader said the records changed after the kept snapshot, and none did: $(jq .recordsNewer <<<"$out")"
}

# Bug: readers that found the snapshot out of date each built one, so 12 to 35 builds ran at once. Two readers at once
# after a new record line start one build between them (the python3 shim counts the builds: each runs cardruns.py
# once), and the kept snapshot then shows the new card. Bug: each of their writers asked GitHub for that one build
# before either took the lock: the issue list is asked once between them too (the gh stub counts the asks).
t_snapkeptonce() {
  local log=$T/$CASE/builds
  snapkept_setup; snapkept_quiet 1; snapkept_new
  snapkept_py "echo build >> '$log'"; echo "echo ask >> '$T/$CASE/asks'; sleep 1" > "$STUB/list-cmd" # sleep: the stub GitHub answers slowly on purpose, so the two readers overlap
  PATH=$T/$CASE/bin:$PATH loop snapshot > "$T/$CASE/a" & PATH=$T/$CASE/bin:$PATH loop snapshot > "$T/$CASE/b"; wait
  jq -e .belt "$T/$CASE/a" > /dev/null && jq -e .belt "$T/$CASE/b" > /dev/null || fail "a reader printed no snapshot"
  snapkept_built
  # A second writer, had it built, would be building now or have noted its build: it is given the time to start.
  sleep 2; snapkept_built # sleep: a second writer is given time to start; a run that never starts cannot be waited for
  [ "$(wc -l < "$log")" = 1 ] || fail "two readers at once ran $(wc -l < "$log") builds, not one"
  [ "$(wc -l < "$T/$CASE/asks")" = 1 ] || fail "two readers at once asked GitHub for the issues $(wc -l < "$T/$CASE/asks") times, not once"
}

# A --fresh call (out0) whose build is held (the python3 shim) until the file go exists, after it read the records,
# and then a new card (c9) in the records: a call that asks now needs a build that begins after its ask to show it.
# The builds are noted in builds, one line each.
snapkept_held() {
  local g=$T/$CASE/github
  snapkept_setup; mkdir -p "$g" && loop github "$g" || fail "the stream's GitHub folder could not be filled"
  snapkept_py "echo build >> '$T/$CASE/builds'; for _ in \$(seq 200); do [ ! -e '$T/$CASE/go' ] || break; sleep 0.1; done" # sleep: the pause between two looks for go, which the case makes when its calls asked
  CONVEYOR_GITHUB=$g PATH=$T/$CASE/bin:$PATH loop snapshot --fresh > "$T/$CASE/out0" &
  # wait: the bug is between calls of the real command while one holds the lock; a function call cannot hold a build
  # open in a second process, so the case polls the running call until its build began
  wait_until "[ -s '$T/$CASE/builds' ]" || fail "the held call's build did not begin"
  snapkept_new
}
snapkept_fresh() { CONVEYOR_GITHUB=$T/$CASE/github PATH=$T/$CASE/bin:$PATH loop snapshot --fresh > "$T/$CASE/out$1"; }
# c9 on the belt of the build the call printed: a card the reader adds from the records (fromRecords: c9's line came
# after that build counted the records) is left out, as it shows c9 whichever build was printed.
snapkept_c9() { jq -e '.belt | map(select(.fromRecords != true) | .card) | index("c9")' "$T/$CASE/out$1" > /dev/null; }

# Bug (#1101): under five starting cards, six `snapshot --fresh` calls ran at once and none replaced the snapshot.
# Bug: a call that came while a build ran printed that build, which read the records before the caller's change
# (/units then waited for its next change with the old belt). Six calls at once while a build runs start one build
# between them after it, and each prints the new card; the held build, from before the card, shows it not.
t_snapkeptfresh() {
  local i
  snapkept_held
  for i in 1 2 3 4 5 6; do snapkept_fresh "$i" & done
  # wait: the bug is six processes asking at once while a build runs; only their live markers show each asked before
  # the held build ends, so the case polls for them rather than calling a function
  wait_until "m=('$ST'/snapshot.json.*.asked); [ \${#m[@]} -ge 7 ]" || fail "the six calls did not all ask"
  : > "$T/$CASE/go"; wait
  [ "$(wc -l < "$T/$CASE/builds")" = 2 ] || fail "six fresh calls at once while a build ran ran $(($(wc -l < "$T/$CASE/builds") - 1)) builds, not one"
  ! snapkept_c9 0 || fail "the held build read the records after the new card: the case shows nothing"
  for i in 1 2 3 4 5 6; do
    snapkept_c9 "$i" || fail "fresh call $i printed a snapshot without the card added before it asked: $(head -c 300 "$T/$CASE/out$i")"
  done
}

# Bug: a build removes the asked marker of a pid it cannot signal (gone, or another user's), and a waiting call whose
# marker was gone took any kept snapshot as begun after its ask (test -nt with no second file): it printed the held
# build, from before its change. With its marker removed as it waits, the call builds its own.
t_snapkeptgone() {
  local held m
  snapkept_held; held=$(echo "$ST"/snapshot.json.*.asked)
  # wait: the bug is a running call whose marker is removed while it waits on the lock; a direct call cannot be
  # paused there, so the case polls until the live call wrote its marker
  snapkept_fresh 1 & wait_until "m=('$ST'/snapshot.json.*.asked); [ \${#m[@]} -ge 2 ]" || fail "the call did not ask"
  for m in "$ST"/snapshot.json.*.asked; do [ "$m" = "$held" ] || rm -f -- "$m"; done
  : > "$T/$CASE/go"; wait
  snapkept_c9 1 || fail "the call whose marker was removed printed a snapshot without the card added before it asked: $(head -c 300 "$T/$CASE/out1")"
}

# Bug (#1101): a --fresh call killed at its caller's time limit left its <pid>.asked marker in the state folder, and
# nothing removed it (25 of them, 24 of gone processes). The next build removes the marker of a pid that is gone and
# keeps the one of a call still running (here this shell).
t_snapkeptasked() {
  local gone
  snapkept_setup
  sh -c 'exit 0' & gone=$!; wait "$gone"
  : > "$ST/snapshot.json.$gone.asked" && : > "$ST/snapshot.json.$$.asked" || fail "the markers could not be written"
  loop snapshot --fresh | jq -e .belt > /dev/null || fail "the fresh snapshot printed no snapshot"
  [ ! -e "$ST/snapshot.json.$gone.asked" ] || fail "the build left the asked marker of the gone pid $gone"
  [ -e "$ST/snapshot.json.$$.asked" ] || fail "the build removed the asked marker of a call still running"
}

# Bug: a build with no `watch` feed read GitHub from a folder it set as GITHUB, so reading() took it for the feed's
# build and asked no Claude usage reading: with a guard set and no reading yet, the snapshot said the reading was
# missing and the loop running while the account was over the guard.
t_snapkeptguard() {
  local out
  snapkept_setup; tune '.tunables.limitTtl = 0'; loop control guard 50 > /dev/null || fail "the guard could not be set"
  out=$(CONVEYOR_LIMIT_CMD='echo "{\"seven_day\":{\"utilization\":60}}"' loop snapshot --fresh) || fail "the fresh snapshot exited non-zero"
  [ "$(jq -c '.health | [.state, .guard.reading, .guard.missing]' <<<"$out")" = '["paused by guard",60,false]' ] \
    || fail "the fresh snapshot did not ask the usage reading: $(jq -c '.health | {state, guard}' <<<"$out")"
}

# Bug: a writer that wrote the new snapshot over the kept one left a reader half a file while it built. Here the build
# is slowed (cardruns.py waits 3 s): while it runs, the kept file is the old one, whole, and the new one is renamed
# into its place (a new inode), not written into it. And the reader that started the writer ends at once, its output
# read to its end (as watch.py reads it): a writer that kept one of its descriptors open (the engine's stderr copy,
# LOGFD) held that read until the build ended.
t_snapkeptrename() {
  local ino t0 out
  snapkept_setup; snapkept_quiet 1; snapkept_new
  ino=$(snapkept_ino); snapkept_py 'sleep 3' # sleep: the stub build is slowed on purpose, so the reader can end while it runs
  t0=${EPOCHREALTIME/[.,]/}
  out=$(PATH=$T/$CASE/bin:$PATH loop snapshot 2>&1) && jq -e .belt <<<"$out" > /dev/null || fail "the reader printed no snapshot: ${out:0:300}"
  t0=$(( (${EPOCHREALTIME/[.,]/} - t0) / 1000 ))
  lim=$(loadlimit 2000 3000) # under the build's 3 s
  [ "$t0" -lt "$lim" ] || fail "the reader's output ended ${t0} ms after it began: it waited for the writer's build (limit $lim ms: 2000 ms times the load factor $CASE_LOAD)"
  # Bug (#1032): the old snapshot, its belt without c9, did not say the records changed after it, so the Foreman's
  # watcher took its empty belt for an idle Conveyor while c9 was in flight. (c9 joins the reader's belt from the
  # records, fromRecords, as a card picked since: the old snapshot's own belt is the rest.)
  jq -e '.recordsNewer == true and (.belt | map(select(.fromRecords != true) | .card) | index("c9") | not)' <<<"$out" > /dev/null \
    || fail "the old snapshot did not say the records changed after it: $(jq -c '{recordsNewer, belt: [.belt[] | [.card, .fromRecords]]}' <<<"$out")"
  wait_until snapkept_building || fail "no writer was building after the reader"
  jq -e '.belt | map(.card) | index("c9") | not' "$ST/snapshot.json" > /dev/null || fail "while the writer built, the kept file was not the old snapshot whole"
  loop snapshot | jq -e .belt > /dev/null || fail "while the writer built, a reader did not print a whole snapshot"
  snapkept_built
  [ "$(snapkept_ino)" != "$ino" ] || fail "the writer wrote into the kept file, not a new one renamed into its place"
  out=$(loop snapshot) && jq -e '.recordsNewer == false and (.belt | map(.card) | index("c9"))' <<<"$out" > /dev/null \
    || fail "the new snapshot, with c9 on its belt, still said the records changed after it: $(jq -c '{recordsNewer, belt: [.belt[].card]}' <<<"$out")"
}

# Bug: the rebuild ran jq on every line of the card records (the pick order, the Declined part: 54 s of a minute's
# build). After one new record line, no jq run of a rebuild reads a line of the records from before it (the jq shim
# counts them), and the rebuild shows the new card.
t_snapkeptlines() {
  local log=$T/$CASE/old.lines out
  snapkept_setup; snapkept_new; snapkept_jq "$log"
  out=$(PATH=$T/$CASE/bin:$PATH loop snapshot --fresh < /dev/null) || fail "the rebuild exited non-zero"
  jq -e '.belt | map(.card) | index("c9")' <<<"$out" > /dev/null || fail "the rebuild does not show the new card: $(jq -c '[.belt[].card]' <<<"$out")"
  [ ! -s "$log" ] || fail "jq read $(awk '{n += $1} END {print n}' "$log") lines of the records from before the new one: $(head -n 8 "$log")"
}

# Bug: a writer with no `watch` feed (a Foreman watcher's plain `snapshot`) asked GitHub while it held the lock, so
# the stream's writer (its own GitHub folder) found the lock held and ended: the Board got no new snapshot until GitHub
# answered. Here GitHub takes 10 s to list the issues: while the plain writer waits on it, the lock is free, and the
# stream's writer puts the new card in place before GitHub answers.
t_snapkeptgithub() {
  local g=$T/$CASE/github
  snapkept_setup; mkdir -p "$g" && loop github "$g" || fail "the stream's GitHub folder could not be filled"
  snapkept_quiet 10; snapkept_new
  echo 'touch "$STUB/asking"; sleep 10; touch "$STUB/answered"' > "$STUB/list-cmd" # sleep: the stub GitHub takes 10 s on purpose, so the stream writer can finish first
  loop snapshot > /dev/null || fail "the plain reader exited non-zero"
  for _ in $(seq 50); do [ ! -e "$STUB/asking" ] || break; sleep 0.1; done
  [ -e "$STUB/asking" ] || fail "the plain reader's writer did not ask GitHub within 5 s"
  flock -n "$ST/snapshot.json.lock" true || fail "the plain writer held the lock while it asked GitHub"
  CONVEYOR_GITHUB=$g loop snapshot > /dev/null || fail "the stream's reader exited non-zero"
  snapkept_built
  [ ! -e "$STUB/answered" ] || fail "the stream's writer put no snapshot in place before GitHub answered the plain writer"
  # The plain writer ends within the case: it finds the kept snapshot up to date once GitHub answers.
  for _ in $(seq 100); do [ ! -e "$STUB/answered" ] || break; sleep 0.2; done
  snapkept_built
}

# Bug (#468): a snapshot with no `watch` feed asked GitHub whether gh is signed in, but not whether GitHub answers, so
# its health said ghReached false with gh auth status succeeding. The stub's gh is signed in and answers; then its gh
# auth status times out ($STUB/unreached): signed in, not reached.
t_snapkeptreach() {
  setup "[$(issue 1 2026-11-01)]"; mkdir -p "$ST"
  [ "$(loop snapshot --fresh | jq -c '.health | [.gh, .ghReached]')" = '[true,true]' ] || fail "a signed-in gh that GitHub answers is not reached: $(ls "$ST/snapgh")"
  : > "$STUB/unreached"
  [ "$(loop snapshot --fresh | jq -c '.health | [.gh, .ghReached]')" = '[true,false]' ] || fail "a gh auth status that timed out reads as GitHub reached"
  # Bug (#490): a snapshot's gh false came with no reason. Its own GitHub folder keeps why (ghwhy): here a timed-out gh auth token.
  : > "$STUB/token-timeout"
  [ "$(loop snapshot --fresh | jq -c '.health | [.gh, .ghWhy]')" = '[false,"gh auth token timed out after 20 s"]' ] || fail "the snapshot does not give why gh is signed out: $(cat "$ST/snapgh/ghwhy")"
}

# Bug (#1101): while a new build took minutes, the reader printed the old snapshot alone, so the Board and the
# Foreman's status showed nothing blocked and nothing building while cards blocked and built. The kept snapshot here
# holds c2, c4 and c5 blocked; since it was made c2 landed, c4 was retried (its lines are gone) and the main-red card
# c3 blocked, and loop.json counts 2 building. The reader's recordsNow, from the records and loop.json, holds c5 and
# c3 (by its name), and the loop's count while its process lives, null once it is gone. The kept lock is held while
# it reads, so no writer replaces the kept snapshot under it.
t_snapkeptnow() {
  local out now dead lk
  snapkept_setup
  snapkept_line c5 5 picked ok 07 '{"title": "five"}' >> "$ST/cards.jsonl" && snapkept_line c5 5 blocked blocked 08 '{"reason": "old block"}' >> "$ST/cards.jsonl" \
    && jq -c '.health.blocked = [{card: "c2", issue: 2, reason: "r2", since: "2026-11-17T10:04:00Z"}, {card: "c4", issue: 4, reason: "r4", since: "2026-11-17T10:04:00Z"},
      {card: "c5", issue: 5, reason: "old block", since: "2026-11-17T10:08:00Z"}]' "$ST/snapshot.json" > "$T/$CASE/kept" && mv "$T/$CASE/kept" "$ST/snapshot.json" \
    || fail "the kept snapshot could not be set"
  snapkept_quiet 20; now=$(export TZ=UTC; printf '%(%Y-%m-%dT%H:%M:%SZ)T' -1)
  { snapkept_line c2 2 landed ok 09 "{\"time\": \"$now\", \"sha\": \"abd\", \"product\": false}"; snapkept_line c3 0 blocked blocked 09 "{\"time\": \"$now\", \"reason\": \"the session made no change\"}"
    snapkept_line c6 6 picked ok 09 "{\"time\": \"$now\", \"title\": \"six\"}"; snapkept_line c6 6 blocked blocked 09 "{\"time\": \"$now\", \"reason\": \"visible to customers or staff: needs Dana's yes: a new button\"}"; } >> "$ST/cards.jsonl"
  jq -cn --argjson p "$$" '{pid: $p, state: "running", building: 2, waiting: 1, running: 4}' > "$ST/loop.json"
  exec {lk}>>"$ST/snapshot.json.lock" && flock "$lk" || fail "the kept lock could not be held"
  out=$(loop snapshot) || fail "the reader exited non-zero"
  # Bug: c6, stopped for the owner's yes since (the pack's owner, Dana), was one of blocked, so the Board showed it
  # with no Approve and the status named it an ordinary block: the readers' list of those waiting was the old one.
  # Bug (#1123): c6, picked since, is on no belt of the kept snapshot, and Needs you showed it untitled: its title is
  # the one its picked line gives (c5 is on no belt and its picked line is older than the snapshot: null).
  # Bug (#1107): the loop's count left out c2, landed since and on the belt until it pushes, so the status said fewer
  # cards on the belt than it held: landed counts it.
  # Bug (#1305): the count left out a card in review or in its Test step: running is loop.json's count of every card
  # in progress.
  # lines names c2, c3 and c6, each with a line since, and not c5, whose lines are older: the Foreman's watcher drops
  # a card it names stuck from the kept snapshot when that card has a line since (#1784).
  jq -e --arg now "$now" '.recordsNewer == true and .recordsNow == {building: 2, waitingCount: 1, running: 4, landed: 1, blocked: [
      {card: "c5", issue: 5, name: null, title: null, reason: "old block", since: "2026-11-17T10:08:00Z"},
      {card: "c3", issue: 0, name: "Main is red (abcdef012345)", title: "red", reason: "the session made no change", since: $now}],
      waiting: [{card: "c6", issue: 6, name: null, title: "six", reason: "visible to customers or staff: needs Dana'"'"'s yes: a new button", since: $now, sentence: "a new button"}], started: [], lines: ["c2", "c3", "c6"]}' <<<"$out" > /dev/null \
    || fail "the reader did not give what the records and loop.json say now: $(jq -c '{recordsNewer, recordsNow}' <<<"$out")"
  dead=$(sh -c 'echo $$'); jq -cn --argjson p "$dead" '{pid: $p, state: "running", building: 2, waiting: 1, running: 4}' > "$ST/loop.json"
  out=$(loop snapshot) && jq -e '.recordsNow | .building == null and .waitingCount == null and .running == null' <<<"$out" > /dev/null \
    || fail "the reader gave the count of a loop whose process is gone: $(jq -c .recordsNow <<<"$out")"
  # One build after the lock is let go: a writer the reads started finds nothing due, so none builds after the case.
  exec {lk}>&-; loop snapshot --fresh > /dev/null || fail "the snapshot after the reads exited non-zero"
}

# Bug caught: loop.json, written at the loop's last turn, still counts a card that landed after it as running, and
# landed counted that card too, so the Foreman's status read "2 on the belt now" for one card. A card loop.json's
# cards name is left to running; one landed before its turn, as in t_snapkeptnow, is counted in landed. c2 lands in
# the second loop.json is written (or the one before): a test of the two times could not tell which came first.
t_snapkeptlanding() {
  local out now
  snapkept_setup
  snapkept_quiet 20
  now=$(export TZ=UTC; printf '%(%Y-%m-%dT%H:%M:%SZ)T' -1)
  jq -cn --argjson p "$$" '{pid: $p, state: "running", building: 1, waiting: 0, running: 1, cards: ["c2"]}' > "$ST/loop.json"
  snapkept_line c2 2 landed ok 09 "{\"time\": \"$now\", \"sha\": \"abd\", \"product\": false}" >> "$ST/cards.jsonl"
  out=$(loop snapshot) || fail "the reader exited non-zero"
  jq -e '.recordsNewer == true and .recordsNow.running == 1 and .recordsNow.landed == 0' <<<"$out" > /dev/null \
    || fail "with loop.json (running 1, cards [c2]) written in the second c2 landed, $now, the reader does not count c2 once: $(jq -c '{recordsNewer, recordsNow}' <<<"$out")"
  loop snapshot --fresh > /dev/null || fail "the snapshot after the read exited non-zero"
}

# Bug caught: the kept snapshot's belt already shows c2 landed and waiting for its push, loop.json still names c2, and
# another card (c9) writes a newer record: landed counted c2 from the kept belt and running counted it too, so the
# status read two cards on the belt for one. A card loop.json's cards name is left to running in both lists. The kept
# lock is held while it reads, so the writer the due snapshot starts cannot replace the kept one under the read.
t_snapkeptkeptlanded() {
  local out lk
  snapkept_setup
  jq -c '.belt |= map(if .card == "c2" then .landed = true else . end)' "$ST/snapshot.json" > "$T/$CASE/kept" && mv "$T/$CASE/kept" "$ST/snapshot.json" \
    || fail "the kept snapshot could not be set"
  snapkept_quiet 20
  jq -cn --argjson p "$$" '{pid: $p, state: "running", building: 0, waiting: 0, running: 1, cards: ["c2"]}' > "$ST/loop.json"
  snapkept_new
  exec {lk}>>"$ST/snapshot.json.lock" && flock "$lk" || fail "the kept lock could not be held"
  out=$(loop snapshot) || fail "the reader exited non-zero"
  # c9 was picked before loop.json was written, which does not name it: not this loop's card (t_snapkeptpicked).
  jq -e '.recordsNewer == true and .recordsNow.running == 1 and .recordsNow.landed == 0' <<<"$out" > /dev/null \
    || fail "with the kept belt showing c2 landed, loop.json (running 1, cards [c2]) and c9's newer line, the reader does not count c2 once: $(jq -c '{recordsNewer, recordsNow}' <<<"$out")"
  exec {lk}>&-; loop snapshot --fresh > /dev/null || fail "the snapshot after the read exited non-zero"
}

# Bug caught (R220): loop.json is written before its turn picks, so a card picked in that turn (c9, picked since the
# kept snapshot) was in neither its running nor its cards, and the Foreman's status read "0 on the belt now" while it
# built. running counts a card of started that loop.json's cards do not name, picked at or after loop.json's last
# write (10:05:30 here; c9 at 10:06, c2 and c3 on the kept belt before it), and only once when they name it.
snapkept_says() { # <running> <cards>: a live loop.json, last written at 10:05:30
  jq -cn --argjson p "$$" --argjson r "$1" --argjson c "$2" '{pid: $p, state: "running", building: $r, waiting: 0, running: $r, cards: $c}' > "$ST/loop.json" \
    && TZ=UTC touch -t 202611171005.30 "$ST/loop.json" || fail "loop.json could not be written"
}
t_snapkeptpicked() {
  local out lk
  snapkept_setup
  snapkept_quiet 20
  snapkept_says 0 '[]'
  snapkept_new
  exec {lk}>>"$ST/snapshot.json.lock" && flock "$lk" || fail "the kept lock could not be held"
  out=$(loop snapshot) || fail "the reader exited non-zero"
  jq -e '.recordsNow.running == 1 and (.recordsNow.started | map(.card)) == ["c9"]' <<<"$out" > /dev/null \
    || fail "with loop.json (running 0, cards []) and c9 picked since, running is not 1: $(jq -c .recordsNow <<<"$out")"
  snapkept_says 1 '["c9"]'
  out=$(loop snapshot) || fail "the reader exited non-zero"
  jq -e '.recordsNow.running == 1' <<<"$out" > /dev/null \
    || fail "with loop.json (running 1, cards [c9]) and c9 picked since, c9 is not counted once: $(jq -c .recordsNow <<<"$out")"
  exec {lk}>&-; loop snapshot --fresh > /dev/null || fail "the snapshot after the read exited non-zero"
}

# Bug caught: the kept snapshot was built after c9's picked line, so c9 is on its belt and not in started; a later
# line of c9 makes the records newer, and running stayed loop.json's 0, so the status read "0 on the belt now" while
# c9 built. A kept belt card not landed, picked after loop.json's last write and not in its cards, is counted.
t_snapkeptonbelt() {
  local out lk
  snapkept_setup
  snapkept_new; loop snapshot --fresh > /dev/null || fail "the snapshot with c9 exited non-zero"
  jq -e '.belt | map(.card) | index("c9")' "$ST/snapshot.json" > /dev/null || fail "the kept snapshot does not hold c9: $(jq -c '.belt | map(.card)' "$ST/snapshot.json")"
  snapkept_quiet 20
  snapkept_says 0 '[]'
  snapkept_line c9 3 worktree ok 07 >> "$ST/cards.jsonl"
  exec {lk}>>"$ST/snapshot.json.lock" && flock "$lk" || fail "the kept lock could not be held"
  out=$(loop snapshot) || fail "the reader exited non-zero"
  jq -e '.recordsNewer == true and .recordsNow.started == [] and .recordsNow.running == 1' <<<"$out" > /dev/null \
    || fail "with c9 on the kept belt, picked after loop.json (running 0, cards []) and with a newer line, running is not 1: $(jq -c '{recordsNewer, recordsNow}' <<<"$out")"
  exec {lk}>&-; loop snapshot --fresh > /dev/null || fail "the snapshot after the read exited non-zero"
}

# Bug (#1334): the snapshot read the open issues only from the stream's copy, which `watch` asks of GitHub once a
# minute, so an issue the loop's own list (issues.json, asked of GitHub before each pick) already held waited up to that
# minute to show in Queue. Here the stream's copy holds #1 to #3 and the loop's list, written after the kept snapshot,
# holds #4 too: a plain reader starts a build (issues.json is one of its inputs), and that build lists #4 in Queue with
# no question to GitHub. The wait is on the background writer the reader starts: only it shows the reader saw the change.
t_snapkeptissues() {
  local g=$T/$CASE/github
  snapkept_setup; mkdir -p "$g" && loop github "$g" || fail "the stream's GitHub folder could not be filled"
  snapkept_quiet 1; touch -t 200001010000 "$g/issues" || fail "the stream's copy could not be dated"
  echo ': > "$STUB/listed"' > "$STUB/list-cmd"
  jq -c ". + [$(issue 4 2026-11-04)]" "$STUB/issues.json" > "$ST/issues.json" || fail "the loop's issues list could not be written"
  CONVEYOR_GITHUB=$g loop snapshot > /dev/null || fail "the reader exited non-zero"
  wait_until "! snapkept_building && jq -e '.queue.next | map(.issue) | index(4)' '$ST/snapshot.json'" \
    "jq -c '[.queue.next[].issue]' '$ST/snapshot.json'" || fail "no build after the loop wrote issues.json listed #4 in Queue"
  [ ! -e "$STUB/listed" ] || fail "the build asked GitHub for the issues, though the loop's list was newer than the stream's copy"
}

# Bug (#1334): a card picked after the kept snapshot's build began was on no belt until a new build ended, which takes
# minutes on a long history, so the Board and /units showed the belt without it. The kept lock is held, so no build
# ends meanwhile: the reader adds c7, picked and briefed since, to the belt from the records (fromRecords: in no full
# build yet), and units-feed.json (put(), dashboard_stream.py, the file /units reads) keeps it on the belt.
t_snapkeptstarted() {
  local out now lk want
  snapkept_setup; snapkept_quiet 20; now=$(export TZ=UTC; printf '%(%Y-%m-%dT%H:%M:%SZ)T' -1)
  { snapkept_line c7 3 picked ok 09 "{\"time\": \"$now\", \"title\": \"seven\"}"; snapkept_line c7 3 brief ok 09 "{\"time\": \"$now\"}"; } >> "$ST/cards.jsonl"
  exec {lk}>>"$ST/snapshot.json.lock" && flock "$lk" || fail "the kept lock could not be held"
  out=$(loop snapshot) || fail "the reader exited non-zero"
  want='[{card: "c7", issue: 3, name: null, title: "seven", step: "build", stepAt: $now, landed: false, fromRecords: true}]'
  jq -e --arg now "$now" ".belt | map(select(.card == \"c7\")) == $want" <<<"$out" > /dev/null \
    || fail "the reader's belt did not show c7, picked since the kept snapshot: $(jq -c '.belt | map({card, step, fromRecords})' <<<"$out")"
  jq -e '.belt | map(.card) | index("c2")' <<<"$out" > /dev/null || fail "the reader's belt lost the kept snapshot's own card c2"
  # The kept Queue held #3 before c7 picked it: shown in Queue and on the belt at once, it would be counted twice.
  jq -e '.queue.next | map(.issue) | index(3)' "$ST/snapshot.json" > /dev/null || fail "the kept snapshot did not queue #3, so the check below proves nothing"
  jq -e '[.queue | (.next, .order, .waiting) | arrays | .[].issue] | index(3) == null' <<<"$out" > /dev/null \
    || fail "the reader still listed #3 in Queue though c7 holds it on the belt: $(jq -c '.queue | {next: [.next[]?.issue], order: [.order[]?.issue]}' <<<"$out")"
  python3 -c 'import json, sys; sys.path.insert(0, sys.argv[1]); import dashboard_stream as s; s.put(sys.argv[2], {"records": [{"repo": "r", "snap": json.load(sys.stdin)}]})' \
    "$SRC/../.claude/scripts" "$T/$CASE" <<<"$out" || fail "the stream's files could not be written"
  jq -e --arg now "$now" ".records[0].snap.belt | map(select(.card == \"c7\")) == $want" "$T/$CASE/units-feed.json" > /dev/null \
    || fail "units-feed.json did not show c7 on the belt: $(jq -c '.records[0].snap.belt' "$T/$CASE/units-feed.json" 2>&1)"
  # One build after the lock is let go: a writer the read started finds nothing due, so none builds after the case.
  exec {lk}>&-; loop snapshot --fresh > /dev/null || fail "the snapshot after the read exited non-zero"
}

# Bug (R29): recordsNow's landed read the rule "Push when a card lands" from the kept snapshot, so a card that landed
# after the owner turned the rule on was left out of the count until a new build ended. The kept snapshot holds the
# rule off; c8 lands since; the count with the rule still off, then with the control record's rule on: one more.
t_snapkeptpush() {
  local lk off on now
  snapkept_setup; loop control rules push=off > /dev/null || fail "the rule could not be turned off"
  jq -c '.control.rules.push = false' "$ST/snapshot.json" > "$T/$CASE/kept" && mv "$T/$CASE/kept" "$ST/snapshot.json" || fail "the kept snapshot could not be set"
  snapkept_quiet 20; now=$(export TZ=UTC; printf '%(%Y-%m-%dT%H:%M:%SZ)T' -1)
  { snapkept_line c8 3 picked ok 09 "{\"time\": \"$now\", \"title\": \"eight\"}"; snapkept_line c8 3 landed ok 09 "{\"time\": \"$now\", \"sha\": \"abe\", \"product\": false}"; } >> "$ST/cards.jsonl"
  exec {lk}>>"$ST/snapshot.json.lock" && flock "$lk" || fail "the kept lock could not be held"
  off=$(loop snapshot | jq '.recordsNow.landed') || fail "the reader exited non-zero with the rule off"
  loop control rules push=on > /dev/null || fail "the rule could not be turned on"
  on=$(loop snapshot | jq '.recordsNow.landed') || fail "the reader exited non-zero with the rule on"
  [[ $off =~ ^[0-9]+$ ]] && [ "$on" = $((off + 1)) ] \
    || fail "with the rule turned on since the kept snapshot (off there), c8 landed since is not counted: landed $off with the rule off, $on with it on"
  exec {lk}>&-; loop snapshot --fresh > /dev/null || fail "the snapshot after the reads exited non-zero"
}

# Bug (R52): a line stamped before a build began, which waited for the records' lock, was appended after the build
# copied the records: the snapshot did not hold it, and recordsNow, which read only the lines stamped since the build
# began, left it out too, so c8's block showed nowhere until the next build. Here the records' lock is held while c8's
# blocked line, stamped 5 s before, waits for it, and the snapshot is built; then the lock is let go.
# Bug (E1): the build kept the records' size, and a line past it was taken as since; a retry of another card then
# took that card's lines out (moveout(), lib/issues.sh), and c8's late line, now before that size, was left out again.
# Here c1's lines are taken out after the build, as `retry` takes out every line of the cards it gives back.
t_snapkeptlate() {
  local rl lk ap t out
  snapkept_setup
  t=$(export TZ=UTC; printf '%(%Y-%m-%dT%H:%M:%SZ)T' $(($(date +%s) - 5)))
  exec {rl}>>"$ST/cards.jsonl" && flock "$rl" || fail "the records' lock could not be held"
  # The append as record() makes it (locked append, lib/records.sh): the line is stamped, then waits for the lock.
  # Neither the appender nor the build keeps a copy of the case's lock descriptor: one would hold the lock on.
  ( exec {rl}>&-; flock 9 && snapkept_line c8 3 blocked blocked 09 "{\"time\": \"$t\", \"reason\": \"late\"}" >> "$ST/cards.jsonl" ) 9>>"$ST/cards.jsonl" & ap=$!
  loop snapshot --fresh > /dev/null {rl}>&- || fail "the snapshot built under the records' lock exited non-zero"
  exec {rl}>&-; wait "$ap" || fail "the blocked line was not appended once the lock was let go"
  jq -e '.health.blocked | map(.card) | index("c8") | not' "$ST/snapshot.json" > /dev/null || fail "the kept snapshot holds c8's block, so the case proves nothing"
  exec {lk}>>"$ST/snapshot.json.lock" && flock "$lk" || fail "the kept lock could not be held"
  out=$(loop snapshot) || fail "the reader exited non-zero"
  jq -e '.recordsNewer == true and (.recordsNow.blocked | map(.card) | index("c8"))' <<<"$out" > /dev/null \
    || fail "the reader did not list c8, blocked by a line appended after the build: $(jq -c '{snapshotAt, recordsNewer, recordsNow}' <<<"$out")"
  grep -vF '"card":"c1"' "$ST/cards.jsonl" > "$T/$CASE/rest" && mv "$T/$CASE/rest" "$ST/cards.jsonl" || fail "c1's lines could not be taken out"
  out=$(loop snapshot) || fail "the reader after the rewrite exited non-zero"
  jq -e '.recordsNow.blocked | map(.card) | index("c8")' <<<"$out" > /dev/null \
    || fail "after c1's lines were taken out of the records, the reader did not list c8, blocked by a line appended after the build: $(jq -c '{snapshotAt, recordsNewer, recordsNow}' <<<"$out")"
  exec {lk}>&-; loop snapshot --fresh > /dev/null || fail "the snapshot after the read exited non-zero"
}

# Bug (R67): recordsNow, with loop.json's counts, was given only when the card records changed after the kept
# snapshot, so when loop.json alone changed the Foreman's status gave the snapshot's old building count. The kept
# snapshot says building 1; loop.json, written since, says 2; the status of what the reader prints says 2.
t_snapkeptloop() {
  local lk out c=$T/$CASE/config
  snapkept_setup
  jq -c '.health += {building: 1, builderCap: 4, waitingCount: 0}' "$ST/snapshot.json" > "$T/$CASE/kept" && mv "$T/$CASE/kept" "$ST/snapshot.json" \
    || fail "the kept snapshot could not be set"
  snapkept_quiet 20
  jq -cn --argjson p "$$" '{pid: $p, state: "running", building: 2, waiting: 0, running: 2}' > "$ST/loop.json"
  exec {lk}>>"$ST/snapshot.json.lock" && flock "$lk" || fail "the kept lock could not be held"
  loop snapshot > "$T/$CASE/snap" || fail "the reader exited non-zero"
  exec {lk}>&-
  mkdir -p "$c/conveyor" && jq -n --arg m "$R" '{records: [{repo: "alpha", main: $m}]}' > "$c/conveyor/host.json" || fail "the host file could not be written"
  out=$(XDG_CONFIG_HOME=$c CONVEYOR_FOREMAN_DIR=$T/$CASE/foreman CONVEYOR_MAIN=$R CONVEYOR_FOREMAN_ASK="cat $T/$CASE/snap" bash "$SRC/foreman/watch-conveyor.sh" --status 2>&1)
  grep -qF '2 of the cap 4' <<<"$out" \
    || fail "the status of a snapshot older than loop.json did not give loop.json's count: $out $(jq -c '{recordsNewer, recordsNow}' "$T/$CASE/snap")"
  loop snapshot --fresh > /dev/null || fail "the snapshot after the read exited non-zero"
}

# Bug (#1583): with no loop.json (the loop does not run on this machine), a snapshot behind newer card records gave
# recordsNow.building as null, a count no reader could read, and /units took it in place of the snapshot's own. The
# counts read from loop.json (building, waitingCount, running) are left out; the rest of recordsNow is still given.
# t_snapkeptnow keeps the count read from a live loop's loop.json.
t_snapkeptnoloop() {
  local lk out
  snapkept_setup
  rm -f "$ST/loop.json"; snapkept_quiet 20; snapkept_new
  exec {lk}>>"$ST/snapshot.json.lock" && flock "$lk" || fail "the kept lock could not be held"
  out=$(loop snapshot) || fail "the reader with no loop.json exited non-zero"
  exec {lk}>&-
  jq -e '.recordsNewer == true and (.recordsNow | type == "object" and (.started | map(.card)) == ["c9"]
      and (has("building") or has("waitingCount") or has("running") | not))' <<<"$out" > /dev/null \
    || fail "with no loop.json and c9 picked since, the reader gave a loop count it cannot read: $(jq -c '{recordsNewer, recordsNow}' <<<"$out")"
  loop snapshot --fresh > /dev/null || fail "the snapshot after the read exited non-zero"
}

# The Board's panels (panels(), .claude/scripts/dashboard_panels.sh) from the snapshot <file> as one record's read, the
# parts beside it (limit, decisions, lanes, Foremen) none: the Board's own jq program, not the page server.
snapkept_board() { # <file>
  ( export HERE=$SRC/../.claude/scripts RUN=$T/$CASE/board OUT=$T/$CASE/board NOW; NOW=$(date +%s)
    iso() { (export TZ=UTC; printf '%(%Y-%m-%dT%H:%M:%SZ)T' "$1"); }
    mkdir -p "$RUN" && . "$HERE/dashboard_panels.sh" || exit 1
    jq -c '{host: "h", local: true, reachable: true, error: null, records: [{repo: "alpha", snap: ., steered: true, repoUrl: null, lastPushAt: null, readAt: .snapshotAt}]}' "$1" > "$RUN/conveyor.json" \
      && echo '{"limit": null}' > "$RUN/limit.json" && echo '{"decisions": null, "unsent": []}' > "$RUN/decisions.json" \
      && echo '{"records": []}' > "$RUN/lanes.json" && echo '{"foremen": null}' > "$RUN/foremen.json" && panels ) 2>&1
}
# Bug (#1633): a card stopped for the owner's yes (c5, issue 3), then `retry 3 --fresh` and a new card of the issue
# picked by the loop's pick before the kept snapshot was built again: the reader added the new card to the belt but
# kept issue 3 among the held issues ("card blocked: retry" on the Foreman's status) and c5 in Needs you, so the owner
# saw a card that was building as blocked and needing them. Bug: the held count (open.split, the Board's "held"
# total) still counted issue 3 once it left the held list. Bug: a land-branch card of issue 1, picked beside c7 of
# issue 1 still stopped for the yes, took c7 out of Needs you, which the next build lists again. The kept lock is held
# from the retry on, as a build that takes minutes leaves the kept snapshot behind.
t_snapkeptretried() {
  local lk out st c9 c8 n
  snapkept_setup
  { snapkept_line c5 3 picked ok 04 '{"title": "three"}'
    snapkept_line c5 3 blocked blocked 05 '{"reason": "visible to customers or staff: needs Dana'"'"'s yes: a new button"}'
    snapkept_line c7 1 picked ok 06 '{"title": "one again"}'
    snapkept_line c7 1 blocked blocked 07 '{"reason": "visible to customers or staff: needs Dana'"'"'s yes: a new page"}'; } >> "$ST/cards.jsonl"
  loop snapshot --fresh > /dev/null || fail "the snapshot with c5 and c7 blocked exited non-zero"
  jq -e '(.needsYou.waiting | map(.card) | index("c5") and index("c7")) and any(.open.held[]; .issue == 3 and any(.reasons[]; .kind == "card" and .step == "blocked"))' \
    "$ST/snapshot.json" > /dev/null || fail "the kept snapshot does not hold c5 and c7 waiting for the yes and issue 3 held by c5: $(jq -c '{w: .needsYou.waiting, h: .open.held}' "$ST/snapshot.json")"
  exec {lk}>>"$ST/snapshot.json.lock" && flock "$lk" || fail "the kept lock could not be held"
  loop retry 3 --fresh > "$T/$CASE/retry.out" 2>&1 || fail "retry 3 --fresh exited non-zero: $(cat "$T/$CASE/retry.out")"
  snapkept_quiet 20
  # The new card of issue 3 as the loop starts it (pick(), lib/pick.sh, given issue 3 alone as the open issues), then
  # a land-branch card of issue 1 (pickbranch(), lib/lane.sh), which c7, blocked, does not stop.
  fx_in 'locked pick "" "" "$(jq -c "map(select(.number == 3))" "$STUB/issues.json")" && locked pickbranch one-again 1 "one again" "$(git -C "$R" rev-parse HEAD)"'
  { read -r c9 n _ && [ "$n" = 3 ] && read -r c8 && [ -n "$c8" ]; } < "$T/$CASE/run.out" || fail "the pick of issue 3 or the land-branch card of issue 1 failed: $(cat "$T/$CASE/run.out")"
  out=$(loop snapshot) || fail "the reader exited non-zero"
  exec {lk}>&-
  printf '%s\n' "$out" > "$T/$CASE/snap"
  jq -e --arg c9 "$c9" --arg c8 "$c8" '(.belt | map(.card) | index($c9) and index($c8)) and all(.open.held[]; .issue != 3)
      and (.open | .split.you + .split.labelOrRule + .split.landed == (.held | length))
      and (.needsYou.waiting | map(.card) | index("c7") and (index("c5") | not))' <<<"$out" > /dev/null \
    || fail "after retry 3 --fresh, $c9 of issue 3 picked and $c8 of issue 1 begun, the reader has issue 3 held, a held count that is not the held list's, or c5 in Needs you or c7 not: $(jq -c '{belt: [.belt[].card], w: .needsYou.waiting, h: .open.held, s: .open.split}' <<<"$out")"
  # The Board's Needs you, built from that read as the Board builds it: its waiting and blocked cards, and every kind
  # it lists (entries).
  snapkept_board "$T/$CASE/snap" > "$T/$CASE/panels" || fail "the Board's panels did not build: $(cat "$T/$CASE/panels")"
  jq -e '.panels.needs.data | ([.cards.waiting[], .cards.blocked[], (.entries[] | .[]) | select(.issue == 3)] == [])
      and (.cards.waiting | map(.card) | index("c7"))' "$T/$CASE/panels" > /dev/null \
    || fail "after retry 3 --fresh and $c9 of issue 3 picked, the Board's Needs you lists issue 3 or not c7: $(jq -c '.panels.needs.data | {cards, entries}' "$T/$CASE/panels")"
  mkdir -p "$T/$CASE/config/conveyor" && jq -n --arg m "$R" '{records: [{repo: "alpha", main: $m}]}' > "$T/$CASE/config/conveyor/host.json" || fail "the host file could not be written"
  st=$(XDG_CONFIG_HOME=$T/$CASE/config CONVEYOR_FOREMAN_DIR=$T/$CASE/foreman CONVEYOR_MAIN=$R CONVEYOR_FOREMAN_ASK="cat $T/$CASE/snap" bash "$SRC/foreman/watch-conveyor.sh" --status 2>&1)
  grep -q '^  #3 ' <<<"$st" && ! grep -qE '#3 \(card blocked|needs you: .*#3\b' <<<"$st" \
    || fail "after retry 3 --fresh and $c9 of issue 3 picked, foreman status lists #3 off the belt, blocked or needing the owner: $st"
  loop snapshot --fresh > /dev/null || fail "the snapshot after the read exited non-zero"
}
