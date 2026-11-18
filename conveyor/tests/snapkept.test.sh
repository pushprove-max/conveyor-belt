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
# GitHub's answers (snapgh/at) too: asked after the kept snapshot's build began, they are taken for a build to come.
snapkept_quiet() { # <s>
  local t; printf -v t '%(%Y%m%d%H%M.%S)T' $(($(date +%s) - $1))
  touch -c -t 200001010000 "$ST/cards.jsonl" "$ST/retried.jsonl" "$ST/control.json" "$ST/snapgh/at" && mkdir -p "$T/$CASE/cards" && touch -t 200001010000 "$T/$CASE/cards" \
    && touch -t "$t" "$ST/snapshot.json" || fail "the fixture's times could not be set"
}
# Waits until no writer holds the kept snapshot's lock and the kept snapshot shows c9.
snapkept_built() {
  for _ in $(seq 100); do
    flock -n "$ST/snapshot.json.lock" true && jq -e '.belt | map(.card) | index("c9")' "$ST/snapshot.json" > /dev/null 2>&1 && return 0
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
  [ "$(jq -cS 'del(.snapshotAt, .snapshotAge)' <<<"$out")" = "$(jq -cS . "$ST/snapshot.json")" ] || fail "the reader did not print the kept snapshot"
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
  # A second writer, had it built, would hold the lock now or have noted its build: it is given the time to start.
  sleep 2; snapkept_built # sleep: a second writer is given time to start; a run that never starts cannot be waited for
  [ "$(wc -l < "$log")" = 1 ] || fail "two readers at once ran $(wc -l < "$log") builds, not one"
  [ "$(wc -l < "$T/$CASE/asks")" = 1 ] || fail "two readers at once asked GitHub for the issues $(wc -l < "$T/$CASE/asks") times, not once"
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
  [ "$t0" -lt 2000 ] || fail "the reader's output ended ${t0} ms after it began: it waited for the writer's build"
  wait_until "! flock -n '$ST/snapshot.json.lock' true" || fail "no writer was building after the reader"
  jq -e '.belt | map(.card) | index("c9") | not' "$ST/snapshot.json" > /dev/null || fail "while the writer built, the kept file was not the old snapshot whole"
  loop snapshot | jq -e .belt > /dev/null || fail "while the writer built, a reader did not print a whole snapshot"
  snapkept_built
  [ "$(snapkept_ino)" != "$ino" ] || fail "the writer wrote into the kept file, not a new one renamed into its place"
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
}
