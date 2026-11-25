#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 60
# The /units fetch, hooks/units-fetch.sh, on fixture host files: it reads the machine's host file for every project
# on it, not only the plugin's own, and the lanes of the session's checkout from that checkout's record.
# Bugs: the fetch reads one project's paths or names (a project-specific worktrees folder, a default record named
# after one project), so /units is blank or wrong for any other project; a host file's records are read out of
# order, or each record's snapshot is asked of the wrong checkout; a session outside the host's records is read
# locally in place of over ssh; the lanes are looked for in a fixed folder in place of the host file's
# lanes.fast.worktree and lanes.research.worktree.
set -uo pipefail
DIR=$(cd "$(dirname "$0")" && pwd -P)
FETCH=$DIR/units-fetch.sh
# Under /tmp, not TMPDIR (long on macOS), with a short name: the kept ssh connection's socket folder must stay short
# enough to be used.
T=$(mktemp -d /tmp/uf.XXXXXX) || exit 1
trap 'rm -rf "$T"' EXIT
fails=0 TAB=$'\t'
ok() { echo "ok [units-fetch]: $1"; }
bad() { echo "FAIL [units-fetch]: $1" >&2; fails=$((fails + 1)); }
same() { # <what> <want> <got>
  if [ "$2" = "$3" ]; then ok "$1"; else bad "$1"; diff <(printf '%s\n' "$2") <(printf '%s\n' "$3") >&2; fi
}

# The fixture units.test.tsx draws /units from: the text of its template, its \t and \n made characters.
WANT=$(printf '%b' "$(sed -n '/^export const TWO_PROJECTS = `/,/^`$/p' "$DIR/fixtures/units-two-projects.ts" | sed '1s/^[^`]*`//; $d')")
printf '%s\n' "$WANT" > "$T/two.txt"

# A machine: its home (with the host file under XDG_CONFIG_HOME), the Conveyor clone the host file's main names, whose
# stub engine prints, for `snapshot`, the fixture's line of the record CONVEYOR_MAIN names (by its folder's name), and
# fails for a record the fixture has no line of, and a checkout per project. Each case is a machine of its own.
machine() { # <case>
  M=$T/$1; H=$M/home
  mkdir -p "$H/.config/conveyor" "$M/clone/conveyor/lib" "$M/bakery" "$M/gadgetlab" "$M/bin"
  cp "$DIR/../conveyor/lib/portable.sh" "$M/clone/conveyor/lib/portable.sh" # the fetch's cut takes its PATH from it
  printf '%s\n' '#!/usr/bin/env bash' '[ "$1" = snapshot ] || exit 2' \
    "awk -F'\\t' -v r=\"\${CONVEYOR_MAIN##*/}\" '\$1 == r { sub(/^[^\\t]*\\t/, \"\"); print; f = 1 } END { exit !f }' '$T/two.txt'" > "$M/clone/conveyor/conveyor.sh"
}
hostfile() { jq -n "$@" > "$H/.config/conveyor/host.json"; }
fetch() { # <checkout> [<arg>]: the fetch's output, the home folder shown as /r/HOME; XC, when set, is the cache folder
  (cd "$1" && unset CONVEYOR_FOREMAN_DIR && HOME=$H XDG_CONFIG_HOME=$H/.config XDG_CACHE_HOME=${XC:-$H/.cache} PATH=$M/bin:$PATH bash "$FETCH" "${@:2}") | sed "s|$H|/r/HOME|g"
}

# D2: a host file with two projects, neither the plugin's own, read in the first one's checkout.
machine two
hostfile --arg c "$M/clone" --arg b "$M/bakery" --arg g "$M/gadgetlab" \
  '{host: "lab", ssh: "lab", main: $c, records: [{repo: "bakery", main: $b}, {repo: "gadgetlab", main: $g}]}'
same 'two projects: their snapshots in the host file order, read here, as the fixture /units draws' "$WANT" "$(fetch "$M/bakery")"
# Bug: the first record was taken for the session's own project, so a session in gadgetlab showed bakery's cards
# with no name and looked for its Fast lane's card among bakery's. The own project is the record whose main is here.
same 'a session in the second project names that project its own' "$(sed '1s/\tbakery$/\tgadgetlab/' <<<"$WANT")" "$(fetch "$M/gadgetlab")"
# D1 (issue 1653): the snapshots are cut in one jq run for every record, so one record whose snapshot fails must print
# null in its place and leave the records after it whole. Bug it catches: a failed record dropped from the list, or
# its failure cutting the records after it.
mkdir -p "$M/ghost"
hostfile --arg c "$M/clone" --arg b "$M/bakery" --arg g "$M/gadgetlab" --arg x "$M/ghost" \
  '{host: "lab", ssh: "lab", main: $c, records: [{repo: "bakery", main: $b}, {repo: "ghost", main: $x}, {repo: "gadgetlab", main: $g}]}'
same "a failed snapshot between two: null in its place, the others whole (units-fetch.sh in $M/bakery, records bakery ghost gadgetlab)" \
  "$(sed -n '/^host/,$p' <<<"$WANT" | sed 1d | awk -v t="ghost${TAB}null" '1; NR == 1 { print t }')" "$(fetch "$M/bakery" | sed -n '/^host/,$p' | sed 1d)"

# No host file: the board says so, naming the paths looked at (XDG_CONFIG_HOME's, then the checkout's; bug: /units
# named ~/.config/conveyor/host.json whatever XDG_CONFIG_HOME was), and the lanes have no record to come from.
machine nofile
rm -f "$H/.config/conveyor/host.json"
same 'no host file: nofile with the paths looked at, and no record for the lanes' \
  "$(printf 'paths\t\t/r/HOME\t\nfast\tnorecord\nhost\t\tnofile\t0\t/r/HOME/xdg/conveyor/host.json\t%s' "$M/bakery/conveyor/host.json")" \
  "$(cd "$M/bakery" && HOME=$H XDG_CONFIG_HOME=$H/xdg PATH=$M/bin:$PATH bash "$FETCH" | sed "s|$H|/r/HOME|g")"

# A checkout that is no record of the host file (the owner's own machine): the snapshots come over ssh to the host
# file's target, here a stub that runs the command it is given.
machine ssh
printf '%s\n' '#!/usr/bin/env bash' 'while [ "$1" = -o ]; do shift 2; done' 'echo "$1" > "$(dirname "$0")/target"' 'bash -c "$2"' > "$M/bin/ssh"
chmod +x "$M/bin/ssh"
mkdir -p "$M/elsewhere"
hostfile --arg c "$M/clone" --arg b "$M/bakery" --arg g "$M/gadgetlab" \
  '{host: "lab", ssh: "owner@lab", main: $c, records: [{repo: "bakery", main: $b}, {repo: "gadgetlab", main: $g}]}'
got=$(fetch "$M/elsewhere")
same 'a checkout outside the records: the snapshots over ssh' "$(sed '1s/\tbakery$/\t/; s/^fast\tnone$/fast\tnorecord/; s/^host\tlab\tlocal\t0$/host\tlab\tssh\t0/' <<<"$WANT")" "$got"
same 'the ssh target is the host file'"'"'s' 'owner@lab' "$(cat "$M/bin/target" 2>/dev/null)"

# The same with an ssh target ssh cannot use: nothing is asked, and the board says the host file is not understood.
# (With no ssh target at all the host file sets up one machine: conveyor/tests/boardone.test.sh, t_boardonereaders.)
machine badssh
hostfile --arg c "$M/clone" --arg b "$M/bakery" '{host: "lab", ssh: "-oProxyCommand=x", main: $c, records: [{repo: "bakery", main: $b}]}'
mkdir -p "$M/elsewhere"
same 'an ssh target ssh cannot use: config' $'paths\t\t/r/HOME\t\nfast\tnorecord\nhost\tlab\tconfig\t0' "$(fetch "$M/elsewhere")"

# The lanes are the worktrees this checkout's record names (~/ is the home folder): the Fast lane's branch, its
# commits ahead of the pack's default branch (trunk here, not main) and its first subject; the Research lane's folder
# for its session logs.
machine lanes
AT=@
g() { git -C "$1" -c user.name=t -c user.email="t${AT}example.com" "${@:2}" >/dev/null 2>&1; }
mkdir -p "$M/bakery/.conveyor" && echo '{"defaultBranch": "trunk"}' > "$M/bakery/.conveyor/project.json"
g "$M/bakery" init -q -b trunk && g "$M/bakery" commit -q --allow-empty -m start \
  && g "$M/bakery" worktree add -q -b lane-12 "$H/lane" && g "$H/lane" commit -q --allow-empty -m 'Bread oven timer'
hostfile --arg c "$M/clone" --arg b "$M/bakery" \
  '{host: "lab", main: $c, records: [{repo: "bakery", main: $b, lanes: {fast: {worktree: "~/lane"}, research: {worktree: "~/research"}}}]}'
RH=/r/HOME
# `feed` with no feed file: no feed of this machine, so no map's record is named (#1667).
same 'the lanes from the host file' "$(printf 'paths\t%s/research\t%s\tbakery\nfast\tok\tlane-12\t1\t0\tBread oven timer\nforemandir\t%s/bakery/conveyor/state/foreman\nhost\t\tfeed\t0' "$RH" "$RH" "$M")" \
  "$(fetch "$M/bakery" feed)"

# The Foreman line (issue 47): read from the Foreman's folder in the project's state folder (conveyor.sh state-dir),
# here the checkout's own conveyor/state/foreman. A stand-in waiter, started by a path that ends as the real one's
# (versions/<commit>/conveyor/foreman/waiter.sh), holds waiter.lock, writes waiter.pid and runs its watchers as its
# children; with "skip <name>" it leaves that watcher out. Bugs: the Foreman's waiter or a watcher was gone, or the
# waiter ran on an old install, and nothing said so.
A=$(printf 'a%.0s' {1..40})
machine foreman
FD=$M/bakery/conveyor/state/foreman
mkdir -p "$FD" "$M/bakery/.conveyor" "$M/v/$A/conveyor/foreman"
echo "{\"plugin\": {\"commit\": \"$A\"}}" > "$M/bakery/.conveyor/project.json"
hostfile --arg c "$M/clone" --arg b "$M/bakery" '{host: "lab", ssh: "lab", main: $c, records: [{repo: "bakery", main: $b}]}'
printf '%s\n' '#!/usr/bin/env bash' 'exec 7>>"$1/waiter.lock"; flock -n 7 || exit 1' \
  'for w in conveyor limit alerts idle; do [ "$w" = "${3:-}" ] && continue; bash "${0%/*}/watch-$w.sh" & done' \
  'printf "%s %s %s %s\n" "$$" "$2" "$PPID" s1 > "$1/waiter.pid"' 'wait' > "$M/v/$A/conveyor/foreman/waiter.sh"
for w in conveyor limit alerts idle; do echo 'sleep 60' > "$M/v/$A/conveyor/foreman/watch-$w.sh"; done
echo 's1 2026-11-15T00:00:00Z' > "$FD/session"
waiter() { # [<watcher left out>]: starts the stand-in in a process group of its own, once its watchers run
  rm -f "$FD/waiter.pid"; set -m; bash "$M/v/$A/conveyor/foreman/waiter.sh" "$FD" "$A" "$@" & WP=$!; set +m
  for _ in $(seq 100); do [ -s "$FD/waiter.pid" ] && [ "$(pgrep -P "$WP" | wc -l)" -ge $((4 - $#)) ] && return; sleep 0.05; done
}
trap 'kill -- -"${WP:-0}" 2>/dev/null; rm -rf "$T"' EXIT
foreman() { fetch "$M/bakery" feed | grep "^foreman$TAB" || echo 'no foreman line'; }
waiter
same 'D1: the role, a live waiter on the current install and its four watchers' \
  "$(printf 'foreman\ts1\t%s\t%s\ts1\t1\t%s\tconveyor:up limit:up alerts:up idle:up\tlistening' "$WP" "$A" "$A")" "$(foreman)"
# Mode `foreman` (the mod's once-a-second look at the role mark and waiter.pid, hooks/units.tsx foremanTick) prints the
# Foreman's folder and line alone, the same line the whole fetch prints. Bug it catches: a mode that reads the host
# or prints other lines, so a /clear took a whole fetch to show, or a line that differs from the fetch's.
same 'the foreman mode prints the Foreman folder and the same foreman line as the whole fetch, and nothing else' \
  "$(printf 'foremandir\t%s\n%s' "$FD" "$(foreman)")" "$(fetch "$M/bakery" foreman)"
same 'the whole fetch names the Foreman folder' "$(printf 'foremandir\t%s' "$FD")" "$(fetch "$M/bakery" feed | grep '^foremandir')"
kill -- -"$WP"; wait "$WP" 2>/dev/null
# Issue 215: and why it ended, from the last line of its log, written over a minute ago.
echo "2026-11-15T00:00:00Z $WP ended: the session's process 77 has ended" > "$FD/waiter.log"; touch -t 200001010000 "$FD/waiter.log"
same 'D3: a waiter.pid whose waiter has exited is no live waiter' \
  "$(printf 'foreman\ts1\t%s\t%s\ts1\t0\t%s\t\tdown: the session'"'"'s process 77 has ended' "$WP" "$A" "$A")" "$(foreman)"
waiter idle
same 'a watcher that is not running is down' \
  "$(printf 'foreman\ts1\t%s\t%s\ts1\t1\t%s\tconveyor:up limit:up alerts:up idle:down\tlistening' "$WP" "$A" "$A")" "$(foreman)"
# A waiter of an older engine (the project pinned to it) writes no session's process: "<pid> <commit> <session>".
# Bug: the session was read from a fourth field only, so /units lost it for that live waiter.
echo "$WP $A s1" > "$FD/waiter.pid"
same 'the waiter.pid of an older engine still names its session' \
  "$(printf 'foreman\ts1\t%s\t%s\ts1\t1\t%s\tconveyor:up limit:up alerts:up idle:down\tlistening' "$WP" "$A" "$A")" "$(foreman)"
kill -- -"$WP"; wait "$WP" 2>/dev/null
# D4: no role mark and no launcher settings: no Foreman is expected, so no line (the other machines above have no
# Foreman folder at all, and their whole output has none).
: > "$FD/session"
same 'D4: a Foreman folder with no role and no setup prints no line' 'no foreman line' "$(foreman)"
# Bug it catches (R439): the folder was named only with a Foreman line, so a poll that found none left the mod with no
# folder to watch, and a claim made after it waited for the minute's poll.
same 'a Foreman folder with no role is still named, so the mod sees a claim made later' "$(printf 'foremandir\t%s' "$FD")" "$(fetch "$M/bakery" feed | grep '^foremandir')"
echo '{}' > "$FD/settings.json"
same 'a set-up Foreman whose role no session holds still prints its line' \
  "$(printf 'foreman\t\t%s\t%s\ts1\t0\t%s\t\tdown: the session'"'"'s process 77 has ended' "$WP" "$A" "$A")" "$(foreman)"
# Issue 139: the plugin problems the Foreman noted (stop.sh writes one "- " line each) are counted, with the file, so
# /units can say so; the file's heading is no problem. Bug it catches: a noted problem /units never showed.
printf '# Plugin problems\n\n- 2026-11-16T10:00:00Z · card #7 · a · evidence: -\n- 2026-11-16T11:00:00Z · card - · b · evidence: -\n' > "$FD/plugin-bugs.md"
same 'the plugin problems noted: how many, and the file' "$(printf 'pluginbugs\t2\t%s' "$FD/plugin-bugs.md")" "$(fetch "$M/bakery" feed | grep '^pluginbugs')"
# Issue 176: while the test map is made, the progress the engine writes beside it (conveyor/lib/testmap.sh) is read;
# a checkout with no project settings (the machines above) prints no testmap line. Bug it catches: /units never
# showed a map's run, so a setup or refresh that ran for many minutes looked like nothing. With the feed fresh, the
# map is not read: the feed's snapshot carries it (#1651). Bug that catches: every minute's fetch ran `conveyor.sh
# testmap` for a map /units already had.
mkdir -p "$M/bakery/.conveyor" && echo '{}' > "$M/bakery/.conveyor/project.json"
echo "{\"pid\": $$, \"started\": 1700000000, \"done\": 3, \"of\": 8}" > "$M/bakery/.conveyor/test-map.run.json"
# The map's record is named with no feed too (#1651 review), by its main: /units keeps it for the feed that comes back
# between two fetches. Bug it catches: a fetch with no feed left /units with no map's record, and the next feed drew no map.
MAPRUN=$(printf 'testmap\t{"state":"running","done":3,"of":8,"started":1700000000}')
MAPREC=$(printf 'maprec\t%s/bakery\nmaphost\t' "$M")
same "the test map being made: its files run of how many, and its start, and its record (units-fetch.sh in $M/bakery)" \
  "$(printf '%s\n%s' "$MAPREC" "$MAPRUN")" "$(fetch "$M/bakery" | grep -E '^(testmap|maprec|maphost)')"
# The Board's feed file (units-feed.json, as .claude/scripts/dashboard_stream.py writes it): its machine (host, and its
# ssh target or local), one record, its repo, its main and whether its stream is live, its snapshot with a test map.
feedfile() { # <repo> <main> <live: true or false> [<host>, lab when not given] [<ssh target>, none (local) when not given]
  jq -n --arg r "$1" --arg m "$2" --argjson l "$3" --arg h "${4:-lab}" --arg s "${5:-}" '{host: $h, local: ($s == ""), ssh: (if $s == "" then null else $s end),
    stream: {live: $l}, records: [{repo: $r, main: $m, snap: {testMap: {state: "made", sources: 1, tests: 1, age: 0}}}]}' > "$T/feed.json"
}
# D2: the feed live, its record of this checkout (by its main) carries the map: the map is not read.
feedfile bakery "$M/bakery" true
same "with the feed live and its record of this checkout, no test map is read (units-fetch.sh feed $T/feed.json in $M/bakery)" \
  "$MAPREC" "$(fetch "$M/bakery" feed "$T/feed.json" | grep -E '^(testmap|maprec|maphost)')"
# The feed's record of this checkout by another path to the same folder is named as the feed names it: /units finds the
# record by that text. Bug it catches: the map was read again, or /units looked for a main the feed does not have.
ln -s "$M/bakery" "$M/bakery-link"
feedfile bakery "$M/bakery-link" true
same "the feed's main is another path to this checkout: the map's record is named by the feed's path (units-fetch.sh feed in $M/bakery)" \
  "$(printf 'maprec\t%s/bakery-link\nmaphost\t' "$M")" "$(fetch "$M/bakery" feed "$T/feed.json" | grep -E '^(testmap|maprec|maphost)')"
# The feed's record of the same name is another checkout's (the Board reads another host file that names bakery for
# it, #1651 review): the map is read. Bug it catches: /units showed the other checkout's map, found by name alone.
feedfile bakery "$M/gadgetlab" true
same "the feed's bakery is another checkout: the map is read (units-fetch.sh feed in $M/bakery, feed bakery on gadgetlab)" \
  "$(printf '%s\n%s' "$MAPREC" "$MAPRUN")" "$(fetch "$M/bakery" feed "$T/feed.json" | grep -E '^(testmap|maprec|maphost)')"
# A feed whose stream is down keeps its last snapshot, so its map can be old: the map is read (#1651 review). Bug it
# catches: /units kept showing a run's old progress after the map was made, while the Board's stream was down.
feedfile bakery "$M/bakery" false
same "the feed's stream is down: the map is read (units-fetch.sh feed in $M/bakery, stream not live)" \
  "$(printf '%s\n%s' "$MAPREC" "$MAPRUN")" "$(fetch "$M/bakery" feed "$T/feed.json" | grep -E '^(testmap|maprec|maphost)')"
# A host file with no records and no main (`{}`) puts its record "project" on whichever checkout reads it (#1651
# review). The Board in this same checkout: its feed's "project" is on this checkout, so the map is not read. The Board
# in another checkout: its "project" is that one, so the map is read. Bugs they catch: with the Board and the session in
# one checkout, every fetch read the map again; in a second checkout, /units showed the Board's checkout's map.
cp "$H/.config/conveyor/host.json" "$T/lanes-host.json"
hostfile '{}'
feedfile project "$M/bakery" true
same "host file {}, the Board in this checkout: no test map is read (units-fetch.sh feed in $M/bakery, feed project on bakery)" \
  "$MAPREC" "$(fetch "$M/bakery" feed "$T/feed.json" | grep -E '^(testmap|maprec|maphost)')"
feedfile project "$M/gadgetlab" true
same "host file {}, the Board in another checkout: the map is read (units-fetch.sh feed in $M/bakery, feed project on gadgetlab)" \
  "$(printf '%s\n%s' "$MAPREC" "$MAPRUN")" "$(fetch "$M/bakery" feed "$T/feed.json" | grep -E '^(testmap|maprec|maphost)')"
# No host file: no machine to hold the feed's to, so no map's record is named and the map is read (#1667). Bug it
# catches: /units took the map of a feed of any machine whose record was at this path.
rm -f "$H/.config/conveyor/host.json"
feedfile bakery "$M/bakery" true
same "no host file, the feed's bakery on this path: the map is read, no maprec (units-fetch.sh feed $T/feed.json in $M/bakery)" \
  "$MAPRUN" "$(fetch "$M/bakery" feed "$T/feed.json" | grep -E '^(testmap|maprec|maphost)')"
# A host file with a build machine (lab at owner@lab) that names this checkout as a record: the fetch reads the map
# here, not over ssh, so a feed of that build machine is of another machine: no map's record is named and the map is
# read here (#1667 review). Bug it catches: /units showed the build machine's map, where without the feed it showed
# this machine's.
hostfile --arg b "$M/bakery" '{host: "lab", ssh: "owner@lab", main: $b, records: [{repo: "bakery", main: $b}]}'
feedfile bakery "$M/bakery" true lab owner@lab
same "a record of a host file at owner@lab, the feed of lab at owner@lab: the map is read here, no maprec (units-fetch.sh feed $T/feed.json in $M/bakery)" \
  "$MAPRUN" "$(fetch "$M/bakery" feed "$T/feed.json" | grep -E '^(testmap|maprec|maphost)')"
cp "$T/lanes-host.json" "$H/.config/conveyor/host.json"
# Issue 179: a project that follows main and runs an older commit on this machine than the newest its last take read
# gets doctor's line, feed or not. Bug it catches: a project stayed on an old engine for hours and /units said nothing.
mkdir -p "$M/bakery/.git" && jq '.plugin = {follow: "main"}' "$DIR/../conveyor/lib/test-pack.json" > "$M/bakery/.conveyor/project.json"
c1=$(printf '1%.0s' {1..40}) c2=$(printf '2%.0s' {1..40})
jq -n --arg c "$c1" --arg h "$c2" '{commit: $c, taken: [$c], head: {commit: $h, name: "main"}}' > "$M/bakery/.git/conveyor-engine.json"
same 'an old engine: the line that names it and the command that takes the newest commit' \
  "$(printf "engine\tConveyor runs an old engine here: commit 1111111, and the plugin's main is at 2222222 · last take that worked: none in the log · last failure: none in the log · to take it, run: cd %s && bash %s/conveyor.sh take" "$M/bakery" "$(cd "$DIR/../conveyor" && pwd -P)")" \
  "$(fetch "$M/bakery" feed | grep '^engine')"
# When Conveyor for this checkout runs on a build machine, the map is that machine's: asked in the snapshots' ssh
# command, of the record named as this checkout's folder, and printed before the host line, as parseFetch reads it;
# with the feed, it is not asked: the feed's snapshot carries it (#1651). Bug it catches: /units showed this machine's
# map, which no run on the build machine makes or refreshes, so it read "being made" or "not made yet" forever; or,
# with the Board's live feed fresh, each minute's fetch still asked the build machine for the map over ssh.
machine buildmap
printf '%s\n' '#!/usr/bin/env bash' 'while [ "$1" = -o ]; do shift 2; done' 'bash -c "$2"' > "$M/bin/ssh" && chmod +x "$M/bin/ssh"
# The stub engine's testmap names the checkout it was asked of; its snapshot is the fixture's, as above. Each command
# it is asked is written to engine.log, so a case can say whether the map was asked at all.
printf '%s\n' '#!/usr/bin/env bash' "echo \"\$1\" >> '$M/engine.log'" '[ "$1" != testmap ] || { echo "{\"state\":\"made\",\"of\":\"$CONVEYOR_MAIN\"}"; exit 0; }' \
  '[ "$1" = snapshot ] || exit 2' "awk -F'\\t' -v r=\"\${CONVEYOR_MAIN##*/}\" '\$1 == r { sub(/^[^\\t]*\\t/, \"\"); print }' '$T/two.txt'" > "$M/clone/conveyor/conveyor.sh"
mkdir -p "$M/dev/bakery/.conveyor" && echo '{}' > "$M/dev/bakery/.conveyor/project.json"
echo "{\"pid\": $$, \"started\": 1700000000, \"done\": 3, \"of\": 8}" > "$M/dev/bakery/.conveyor/test-map.run.json"
hostfile --arg c "$M/clone" --arg b "$M/bakery" --arg g "$M/gadgetlab" \
  '{host: "lab", ssh: "owner@lab", main: $c, records: [{repo: "gadgetlab", main: $g}, {repo: "bakery", main: $b}]}'
got=$(fetch "$M/dev/bakery")
same 'a build machine: its map, of the record named as this checkout, before the host line' \
  "$(printf 'testmap\t{"state":"made","of":"%s"}\nhost\tlab\tssh\t0' "$M/bakery")" "$(grep -E '^(testmap|host)' <<<"$got")"
same 'a build machine: every record still has its snapshot' 'gadgetlab bakery' "$(sed -n '/^host/,$p' <<<"$got" | sed 1d | cut -f1 | tr '\n' ' ' | sed 's/ $//')"
same "a build machine with no feed: the map is asked of its engine (units-fetch.sh in $M/dev/bakery)" 'testmap' "$(grep -x testmap "$M/engine.log")"
rm -f "$M/engine.log"
# The feed's map is that of the record named as this checkout's folder, on the main the host file gives it, as the ssh
# map's is: no record's main is this checkout here, so the own of the paths line is empty. Bug it catches: /units
# showed no map on a build machine with the feed.
# D2 of #1667: the feed is of this session's build machine (owner@lab, as this host file names it), though the Board's
# host file names it oven: host names are not compared. Bug it catches (#1667 review): a feed of the same machine by
# another name was taken as another machine's, and each fetch asked the map over ssh.
feedfile bakery "$M/bakery" true oven owner@lab
same "a build machine with the feed: no map and no snapshots, the map's record the folder's (units-fetch.sh feed in $M/dev/bakery, host file lab at owner@lab, feed oven at owner@lab)" \
  "$(printf 'maprec\t%s/bakery\nmaphost\towner@lab\nhost\t\tfeed\t0' "$M")" "$(fetch "$M/dev/bakery" feed "$T/feed.json" | grep -E '^(testmap|maprec|maphost|host|gadgetlab|bakery)')"
same "a build machine with the feed: its engine is asked nothing (units-fetch.sh feed in $M/dev/bakery)" '' "$(cat "$M/engine.log" 2>/dev/null)"
# The feed's bakery is on another main than this host file's: the map is asked of the build machine, as with no feed.
# Bug it catches: the fetch read no map, and /units showed another checkout's map, found by name alone.
feedfile bakery "$M/gadgetlab" true lab owner@lab
same "a build machine, the feed's bakery on another main: the map is asked over ssh (units-fetch.sh feed in $M/dev/bakery)" \
  "$(printf 'maprec\t%s/bakery\nmaphost\towner@lab\ntestmap\t{"state":"made","of":"%s/bakery"}' "$M" "$M")" "$(fetch "$M/dev/bakery" feed "$T/feed.json" | grep -E '^(testmap|maprec|maphost)')"
# #1667: the Board reads another build machine, whose bakery is at the same path as this host file's: by another host
# name (oven), or by the same host name at another ssh target (lab at owner@oven). The map is asked of this session's
# build machine, as with no feed, and no map's record is named. Bug it catches: /units showed the other machine's map,
# its record matched by path, or by path and host name, alone.
MAPSSH=$(printf 'testmap\t{"state":"made","of":"%s/bakery"}' "$M")
feedfile bakery "$M/bakery" true oven owner@oven
same "a build machine, the feed of oven at owner@oven with bakery at the same path: the map is asked over ssh (units-fetch.sh feed $T/feed.json in $M/dev/bakery, host file lab at owner@lab)" \
  "$MAPSSH" "$(fetch "$M/dev/bakery" feed "$T/feed.json" | grep -E '^(testmap|maprec|maphost)')"
feedfile bakery "$M/bakery" true lab owner@oven
same "a build machine, the feed of lab at owner@oven with bakery at the same path: the map is asked over ssh (units-fetch.sh feed $T/feed.json in $M/dev/bakery, host file lab at owner@lab)" \
  "$MAPSSH" "$(fetch "$M/dev/bakery" feed "$T/feed.json" | grep -E '^(testmap|maprec|maphost)')"
# A feed of an older Board names no ssh target and is not local: it does not say which machine it reads, so the map
# is asked over ssh (#1667 review). Bug it catches: a missing ssh target was taken as a match, and /units showed the
# map of that Board's machine.
jq -n --arg m "$M/bakery" '{host: "lab", local: false, stream: {live: true}, records: [{repo: "bakery", main: $m, snap: {testMap: {state: "made", sources: 1, tests: 1, age: 0}}}]}' > "$T/feed.json"
same "a build machine, the feed of an older Board with no ssh and bakery at the same path: the map is asked over ssh (units-fetch.sh feed $T/feed.json in $M/dev/bakery, host file lab at owner@lab)" \
  "$MAPSSH" "$(fetch "$M/dev/bakery" feed "$T/feed.json" | grep -E '^(testmap|maprec|maphost)')"

# The short check (issue 1033): `stamp` prints one checksum a record, of its state folder's cards.jsonl, control.json
# and queue, in one command (one ssh command for every record); `fresh <repo>` asks that record for a snapshot built
# now. The stub engine names each checkout's state folder, and its snapshot is the kept one (health state "kept") unless
# --fresh, then the last line of cards.jsonl as its health. Bugs it catches: a card started showed only at the next minute's fetch, and then from a
# kept snapshot older than it; a check asked the host once a record, or moved for a record nothing changed in.
# The ssh stub logs each command it runs; a kept connection's -O check, which runs nothing on the host, finds none.
machine stamp
printf '%s\n' '#!/usr/bin/env bash' 'case $1 in' 'state-dir) echo "$CONVEYOR_MAIN/state" ;;' \
  'snapshot) if [ "${2-}" = --fresh ]; then tail -n 1 "$CONVEYOR_MAIN/state/cards.jsonl" | jq -c "{health: .}"; else echo "{\"health\":{\"state\":\"kept\"}}"; fi ;;' '*) exit 2 ;;' 'esac' > "$M/clone/conveyor/conveyor.sh"
printf '%s\n' '#!/usr/bin/env bash' 'while [ "$1" = -o ]; do shift 2; done' '[ "$1" != -O ] || exit 255' 'echo x >> "$(dirname "$0")/calls"' 'bash -c "$2"' > "$M/bin/ssh" && chmod +x "$M/bin/ssh"
mkdir -p "$M/bakery/state" "$M/gadgetlab/state" "$M/elsewhere"
echo '{"step":"landed"}' > "$M/bakery/state/cards.jsonl"
hostfile --arg c "$M/clone" --arg b "$M/bakery" --arg g "$M/gadgetlab" \
  '{host: "lab", ssh: "owner@lab", main: $c, records: [{repo: "bakery", main: $b}, {repo: "gadgetlab", main: $g}]}'
s1=$(fetch "$M/bakery" stamp)
same 'stamp: a stamps line, then a record line each, here' 'stamps local|bakery|gadgetlab' "$(cut -f1,2 <<<"$s1" | sed 's/\t[0-9].*//' | tr '\t\n' ' |' | sed 's/|$//')"
same 'stamp: nothing changed, the same checksums' "$s1" "$(fetch "$M/bakery" stamp)"
echo '{"step":"start","card":"c9"}' >> "$M/bakery/state/cards.jsonl"
s2=$(fetch "$M/bakery" stamp)
same 'stamp: a start line moves its record'"'"'s checksum, and only its' 'bakery' "$(diff <(echo "$s1") <(echo "$s2") | sed -n 's/^> \([^\t]*\)\t.*/\1/p')"
# A step only a live record writes (a proof run between recorded steps, a fix after a GO) moves the checksum too;
# the live record's other fields, rewritten all through a step, do not. bakery keeps its cards folder's name.
echo conveyor-cards-bakery > "$M/bakery/state/cards-folder"
mkdir -p "$M/conveyor-cards-bakery/mainrun"
echo '{"step":"review","at":"t1","last":"t1","turns":1}' > "$M/conveyor-cards-bakery/c9.live"
s2=$(fetch "$M/bakery" stamp)
echo '{"step":"review","at":"t1","last":"t2","turns":5}' > "$M/conveyor-cards-bakery/c9.live"
same 'stamp: a live record'"'"'s heartbeat moves no checksum' "$s2" "$(fetch "$M/bakery" stamp)"
echo '{"step":"fix","at":"t3","last":"t3","turns":0}' > "$M/conveyor-cards-bakery/c9.live"
s3=$(fetch "$M/bakery" stamp)
same 'stamp: a live record'"'"'s new step moves its record'"'"'s checksum' 'bakery' "$(diff <(echo "$s2") <(echo "$s3") | sed -n 's/^> \([^\t]*\)\t.*/\1/p')"
echo '{"at":"t4"}' > "$M/conveyor-cards-bakery/mainrun/c9.unfixed.live"
s4=$(fetch "$M/bakery" stamp)
same 'stamp: a proof run started moves its record'"'"'s checksum' 'bakery' "$(diff <(echo "$s3") <(echo "$s4") | sed -n 's/^> \([^\t]*\)\t.*/\1/p')"
s2=$s4
same 'stamp: over ssh, the same checksums in one call' "$(sed 's/^stamps\tlocal$/stamps\tssh/' <<<"$s2")|x" "$(fetch "$M/elsewhere" stamp)|$(cat "$M/bin/calls")"
got=$(fetch "$M/bakery" fresh bakery)
same 'fresh: the changed record'"'"'s snapshot holds the change, the other'"'"'s is the kept one' \
  "$(printf 'bakery\t{"health":{"step":"start","card":"c9"}}\ngadgetlab\t{"health":{"state":"kept"}}')" "$(sed -n '/^host/,$p' <<<"$got" | sed 1d)"

# Issue 1653: each record's state folder is kept with a key of what the engine reads to name it: the host file (its
# time and its file, a link followed) and the folder each checkout the host file names, and its conveyor/state, leads
# to. So a stamp while the key stays asks the engine for none (bug: every 5 s stamp started the engine once a record);
# a host file that names another state folder is read at the next stamp, here through a link to it whose own time does
# not change (bugs: a kept folder outlived the host file's change; the link's time was read, not its file's); a link
# that gives two checkouts one folder asks the engine again, which refuses it (bug: the kept folders went round that
# refusal). The stub engine names the folders as lib/paths.sh does: the stateDir is the host main's (its main, else
# its first record's), else its conveyor/state, and every other record's is its conveyor/state; it refuses two
# checkouts that lead to one folder, and counts each time it is asked in sdcalls. The host file's times are set in
# the past: one changed in this second keeps no folder.
cat > "$T/sdstub.sh" <<'EOF'
#!/usr/bin/env bash
[ "$1" = state-dir ] || exit 2
echo x >> "$XDG_CONFIG_HOME/sdcalls"
h=$XDG_CONFIG_HOME/conveyor/host.json hm=$(jq -r '.main // .records[0].main' "$h")
st() { if [ "$1" = "$hm" ]; then jq -r --arg d "$1/conveyor/state" '.stateDir // $d' "$h"; else echo "$1/conveyor/state"; fi; }
seen=' '
for m in $(jq -r '.main // empty, .records[].main' "$h" | sort -u); do p=$(cd "$(st "$m")" 2>/dev/null && pwd -P) || continue; case $seen in *" $p "*) exit 1 ;; esac; seen="$seen$p "; done
st "$CONVEYOR_MAIN"
EOF
sdcalls() { wc -l < "$H/.config/sdcalls" | tr -d ' '; }
machine stampcache
mkdir -p "$M/bakery/conveyor/lib" "$M/bakery/conveyor/state" "$M/gadgetlab/conveyor/state" "$M/moved"
cp "$T/sdstub.sh" "$M/bakery/conveyor/conveyor.sh"; cp "$DIR/../conveyor/lib/portable.sh" "$M/bakery/conveyor/lib/"
echo '{"step":"landed"}' > "$M/bakery/conveyor/state/cards.jsonl"; echo '{"step":"moved"}' > "$M/moved/cards.jsonl"
ln -s "$H/.config/conveyor/kept.json" "$H/.config/conveyor/host.json"
hostfile --arg b "$M/bakery" --arg g "$M/gadgetlab" '{host: "lab", ssh: "owner@lab", main: $b, records: [{repo: "bakery", main: $b}, {repo: "gadgetlab", main: $g}]}'
touch -t 202601010000 "$H/.config/conveyor/kept.json"; touch -h -t 202601010000 "$H/.config/conveyor/host.json"
s5=$(fetch "$M/bakery" stamp)
same "stamp: a second stamp with the host file unchanged reads the kept state folders (units-fetch.sh stamp in $M/bakery)" \
  "$s5|2" "$(fetch "$M/bakery" stamp)|$(sdcalls)"
hostfile --arg b "$M/bakery" --arg g "$M/gadgetlab" --arg s "$M/moved" \
  '{host: "lab", ssh: "owner@lab", main: $b, stateDir: $s, records: [{repo: "bakery", main: $b}, {repo: "gadgetlab", main: $g}]}'
touch -t 202601010001 "$H/.config/conveyor/kept.json"
same "stamp: the host file, behind a link, names another state folder for its main, bakery: the next stamp reads it (units-fetch.sh stamp in $M/bakery)" \
  "bakery|4" "$(diff <(echo "$s5") <(fetch "$M/bakery" stamp) | sed -n 's/^> \([^\t]*\)\t.*/\1/p')|$(sdcalls)"
rmdir "$M/gadgetlab/conveyor/state" && ln -s "$M/moved" "$M/gadgetlab/conveyor/state"
same "stamp: gadgetlab's conveyor/state made a link to bakery's stateDir, host file unchanged: the engine is asked again (units-fetch.sh stamp in $M/bakery)" \
  6 "$(fetch "$M/bakery" stamp > /dev/null; sdcalls)"
# The same, with a host main that is no record (bug: the kept folders were only the records', so a link that gave the
# host main's conveyor/state a record's folder went round the engine's refusal).
machine stamphm
mkdir -p "$M/clone/conveyor/state" "$M/bakery/conveyor/state" "$M/gadgetlab/conveyor/state"
cp "$T/sdstub.sh" "$M/clone/conveyor/conveyor.sh"
hostfile --arg c "$M/clone" --arg b "$M/bakery" --arg g "$M/gadgetlab" '{host: "lab", ssh: "owner@lab", main: $c, records: [{repo: "bakery", main: $b}, {repo: "gadgetlab", main: $g}]}'
touch -t 202601010000 "$H/.config/conveyor/host.json"
fetch "$M/bakery" stamp > /dev/null; fetch "$M/bakery" stamp > /dev/null; n=$(sdcalls)
rmdir "$M/clone/conveyor/state" && ln -s "$M/bakery/conveyor/state" "$M/clone/conveyor/state"
same "stamp: the host main's (no record's) conveyor/state made a link to bakery's, host file unchanged: the engine is asked again (units-fetch.sh stamp in $M/bakery)" \
  "2|4" "$n|$(fetch "$M/bakery" stamp > /dev/null; sdcalls)"
# On one machine (no ssh target), where the engine is this copy of Conveyor: its own state-dir is the reader whose
# refusal the kept folders must not go round. After two stamps, a change that only makes the engine refuse bakery's
# folder (a broken host file link under XDG_CONFIG_HOME, which it reads and fails on; a host main that was not there
# made, which then shares its stateDir with bakery) gives bakery's next stamp line another checksum, of no folder. Bugs:
# a broken link was taken as no host file, and a host main not there as the folder it would be, so the kept folder
# was read.
machine stamplocal
mkdir -p "$M/bakery/conveyor/state"; echo '{"step":"landed"}' > "$M/bakery/conveyor/state/cards.jsonl"
jq -n --arg b "$M/bakery" '{records: [{repo: "bakery", main: $b}]}' > "$M/bakery/conveyor/host.json"
s6=$(fetch "$M/bakery" stamp); fetch "$M/bakery" stamp > /dev/null
ln -s "$H/.config/conveyor/gone.json" "$H/.config/conveyor/host.json"
same "stamp: a broken host file link added, which the engine refuses: bakery's line changes (units-fetch.sh stamp in $M/bakery, host file $M/bakery/conveyor/host.json)" \
  bakery "$(diff <(echo "$s6") <(fetch "$M/bakery" stamp) | sed -n 's/^> \([^\t]*\)\t.*/\1/p')"
rm "$H/.config/conveyor/host.json"
hostfile --arg b "$M/bakery" --arg m "$M/hm" '{main: $m, stateDir: "\($b)/conveyor/state", records: [{repo: "bakery", main: $b}]}'
touch -t 202601010000 "$H/.config/conveyor/host.json"
s7=$(fetch "$M/bakery" stamp); fetch "$M/bakery" stamp > /dev/null
mkdir "$M/hm"
same "stamp: the host main $M/hm made, its stateDir bakery's folder, which the engine refuses: bakery's line changes (units-fetch.sh stamp in $M/bakery)" \
  bakery "$(diff <(echo "$s7") <(fetch "$M/bakery" stamp) | sed -n 's/^> \([^\t]*\)\t.*/\1/p')"

# Bug (issue 1287): a snapshot printed whole, with the Tests page's history (tests, testActions) and every declined line,
# grew past what the fetch could read in time, and past the cap, though the pane draws none of it. The stub engine prints
# a snapshot with a large tests part; the fetch prints only the parts the pane draws, the judge's declined lines cut to
# id, who and time, and open cut to its two lists. Bug: the cut dropped recordsNow, so
# /units read from the host counted the kept belt's rows against the cap, not loop.json's count now; of it the cut keeps
# building and waitingCount alone. Bug (issue 1679): the cut dropped waitingCount, so /units gave the old snapshot's
# waiting count beside the slots now.
machine cut
printf '%s\n' '#!/usr/bin/env bash' '[ "$1" = snapshot ] || exit 2' \
  "jq -nc '{recordsNewer: true, recordsNow: {building: 1, waitingCount: 3, running: 2, blocked: [], waiting: [], started: [{card: \"c2\"}]}, health: {state: \"ok\"}, belt: [], queue: {next: []}, cost: {today: 1}, snapshotAt: \"t\", tests: [range(0; 3000) | {file: \"f\\(.)\", log: (\"x\" * 1000)}], testActions: [range(0; 5)], declined: [{id: \"a\", by: \"judge\", time: \"t1\", why: \"long\"}, {id: \"b\", by: \"owner\", time: \"t2\"}], declinedRest: [], open: {umbrellas: [{issue: 1}], held: [], issues: [range(0; 50)]}}'" > "$M/clone/conveyor/conveyor.sh"
hostfile --arg c "$M/clone" --arg b "$M/bakery" '{host: "lab", ssh: "lab", main: $c, records: [{repo: "bakery", main: $b}]}'
got=$(fetch "$M/bakery" | sed -n '/^host/,$p' | sed 1d)
same 'the snapshot the host fallback prints holds only what the pane draws, whatever the Tests page holds' \
  'bakery	{"recordsNow":{"building":1,"waitingCount":3},"health":{"state":"ok"},"belt":[],"queue":{"next":[]},"cost":{"today":1},"snapshotAt":"t","declined":[{"id":"a","by":"judge","time":"t1"}],"declinedRest":[],"open":{"umbrellas":[{"issue":1}],"held":[]}}' "$got"
[ "${#got}" -lt 1000 ] && ok 'the cut snapshot is small' || bad "the cut snapshot is ${#got} characters"

# Bug (issue 1287, review): on a macOS build machine jq is Homebrew's, which an ssh command's PATH does not hold; the
# engine adds it to PATH itself (lib/portable.sh p_path), so the snapshot was made and the cut then failed, and the
# pane read null. The ssh stub runs the command on a PATH with no jq, on a host that says Darwin, whose Homebrew folder
# ($M/bin, by the brew stub's place) holds jq: the cut must take that folder from p_path.
machine darwin
mkdir -p "$M/rbin" "$M/elsewhere"
ln -s "$(command -v jq)" "$M/bin/jq"; ln -s "$(command -v dirname)" "$M/rbin/dirname"; ln -s "$(command -v env)" "$M/rbin/env"; ln -s "$(command -v bash)" "$M/rbin/bash"
printf '%s\n' '#!/bin/sh' 'echo Darwin' > "$M/rbin/uname"; printf '%s\n' '#!/bin/sh' 'exit 0' > "$M/rbin/brew"; chmod +x "$M/rbin/uname" "$M/rbin/brew"
printf '%s\n' '#!/usr/bin/env bash' "printf '%s\\n' '{\"health\":{\"state\":\"ok\"},\"tests\":[1,2]}'" > "$M/clone/conveyor/conveyor.sh"
printf '%s\n' '#!/usr/bin/env bash' 'while [ "$1" = -o ]; do shift 2; done' "PATH=$M/rbin $(command -v bash) -c \"\$2\"" > "$M/bin/ssh" && chmod +x "$M/bin/ssh"
hostfile --arg c "$M/clone" --arg b "$M/bakery" '{host: "lab", ssh: "lab", main: $c, records: [{repo: "bakery", main: $b}]}'
same 'over ssh with no jq on its PATH, the cut still takes the engine'"'"'s PATH and the snapshot is kept' \
  'bakery	{"health":{"state":"ok"}}' "$(fetch "$M/elsewhere" | sed -n '/^host/,$p' | sed 1d)"

# Issue 1653: over ssh, the stamp and the poll share one kept connection (ControlMaster=auto, ControlPersist=120, its
# socket in a folder only this user can open). Bugs it catches: every 5 s stamp and every poll logged in to the build
# machine again; a kept connection whose network went dead made each call wait out its time and fail; a kept
# connection outlived a change of the host its ssh alias resolves to. The ssh stub does what OpenSSH does by the
# ControlPath it is given, its %C the checksum of the host the target resolves to (the file resolved, else the
# target): -O check passes while a socket's ssh runs (live or hung); with no socket there, or a stale one (no ssh
# behind it), a call connects anew and, asked to keep the connection for 120 s, leaves a socket that says live; a live
# socket is reused; through a hung one a call waits, as through a kept ssh whose network is dead; -O exit takes the
# socket away. Each call's way is logged: new, reuse, probe (the `true` that tries a kept connection), hung or exit.
# As OpenSSH does, it fails (255) for a ControlPath with a space (which splits the option) or a % that is not %C or %%.
machine mux
mkdir -p "$M/elsewhere"
cat > "$M/bin/ssh" <<'EOF'
#!/usr/bin/env bash
cp='' keep=0 op=''
while :; do case ${1-} in -o) case $2 in ControlPath=*) cp=${2#*=} ;; ControlMaster=auto|ControlPersist=120) keep=$((keep + 1)) ;; esac; shift 2 ;; -O) op=$2; shift 2 ;; *) break ;; esac; done
t=${cp//%%/} t=${t//%C/}; case $t in *[[:space:]]* | *%*) echo "ssh: bad ControlPath $cp" >&2; exit 255 ;; esac
l=${0%/*}/log r=$(cat "${0%/*}/resolved" 2>/dev/null || echo "$1"); r=$(cksum <<<"$r"); cp=${cp//%C/${r%% *}}
s=none; [ -z "$cp" ] || [ ! -e "$cp" ] || s=$(cat "$cp")
case $op in
  check) [ "$s" = live ] || [ "$s" = hung ]; exit ;;
  exit) echo exit >> "$l"; rm -f "$cp"; exit 0 ;;
esac
w=reuse; [ "$2" != true ] || w=probe
case $s in
  live) echo "$w" >> "$l" ;;
  hung) echo hung >> "$l"; exec sleep 30 ;;
  *) echo new >> "$l"; [ -z "$cp" ] || [ "$keep" != 2 ] || echo live > "$cp" ;;
esac
exec bash -c "$2"
EOF
chmod +x "$M/bin/ssh"
hostfile --arg c "$M/clone" --arg b "$M/bakery" --arg g "$M/gadgetlab" \
  '{host: "lab", ssh: "owner@lab", main: $c, records: [{repo: "bakery", main: $b}, {repo: "gadgetlab", main: $g}]}'
s1=$(fetch "$M/elsewhere" stamp); s2=$(fetch "$M/elsewhere" stamp); got=$(fetch "$M/elsewhere")
same "over ssh: the second stamp and the poll go through the connection the first one kept (units-fetch.sh stamp, stamp, then a poll, in $M/elsewhere)" \
  'new probe reuse probe reuse' "$(paste -sd' ' "$M/bin/log")"
same 'over ssh: the stamps through the kept connection are the same' "$s1" "$s2"
same 'over ssh: the poll through the kept connection prints the snapshots as the fixture /units draws' \
  "$(sed '1s/\tbakery$/\t/; s/^fast\tnone$/fast\tnorecord/; s/^host\tlab\tlocal\t0$/host\tlab\tssh\t0/' <<<"$WANT")" "$got"
same 'over ssh: the socket'"'"'s folder is this user'"'"'s alone' 'drwx------' "$(ls -ld "$H/.cache/conveyor/ssh" | cut -c1-10)"
sk=$(find "$H/.cache/conveyor/ssh" -type f) && echo hung > "$sk"; : > "$M/bin/log"
same "over ssh: a kept connection that does not answer is stopped and the stamp asked on a new one (units-fetch.sh stamp in $M/elsewhere, socket hung)" \
  "$s1|hung exit new" "$(fetch "$M/elsewhere" stamp)|$(paste -sd' ' "$M/bin/log")"
echo stale > "$sk"; : > "$M/bin/log"
same "over ssh: a stale socket, no ssh behind it, gives a new connection (units-fetch.sh stamp in $M/elsewhere, socket stale)" \
  "$s1|new" "$(fetch "$M/elsewhere" stamp)|$(paste -sd' ' "$M/bin/log")"
echo lab2 > "$M/bin/resolved"; : > "$M/bin/log"
same "over ssh: the alias owner@lab now resolves to another host: a new connection, not the old host's (units-fetch.sh stamp in $M/elsewhere)" \
  "$s1|new" "$(fetch "$M/elsewhere" stamp)|$(paste -sd' ' "$M/bin/log")"
# A cache folder ssh cannot take as a socket folder (a space or a % in it, or too long a path) keeps the connection in
# /tmp/conveyor-ssh-<user id>. Bugs it catches: a space or a % failed every stamp and poll; a long cache folder kept no
# connection. Each input resolves to a host of its own, this run's, so its socket there is new and is taken away after.
n=0
for xc in "$T/mux/a b" "$T/mux/a%b" "$T/mux/a-cache-folder-too-long-for-a-socket-path"; do
  n=$((n + 1)); echo "lab-$$-$n" > "$M/bin/resolved"; : > "$M/bin/log"; r=$(cksum < "$M/bin/resolved"); r=/tmp/conveyor-ssh-$UID/${r%% *}
  same "over ssh, cache folder $xc: two stamps go through one connection kept in /tmp/conveyor-ssh-$UID (units-fetch.sh stamp, stamp in $M/elsewhere)" \
    "$s1|$s1|new probe reuse|live" "$(XC=$xc fetch "$M/elsewhere" stamp)|$(XC=$xc fetch "$M/elsewhere" stamp)|$(paste -sd' ' "$M/bin/log")|$(cat "$r" 2>/dev/null)"
  rm -f "$r"
done
# Under umask 000, the socket folder is open to this user alone as mkdir makes it (bug: it was made open to all users,
# and only closed by a chmod after). A mkdir in front of the real one logs the mode of the socket folder it makes.
cat > "$M/bin/mkdir" <<'EOF'
#!/usr/bin/env bash
PATH=${PATH//"${0%/*}:"/} mkdir "$@" || exit
for a; do :; done; case $a in */conveyor/ssh) ls -ld "$a" | cut -c1-10 >> "${0%/*}/mkdirs" ;; esac
EOF
chmod +x "$M/bin/mkdir"; echo "lab-$$-umask" > "$M/bin/resolved"
same "over ssh under umask 000, a new cache folder $T/c: mkdir makes its socket folder open to this user alone (units-fetch.sh stamp in $M/elsewhere)" \
  "$s1|drwx------" "$(umask 000; XC=$T/c fetch "$M/elsewhere" stamp)|$(cat "$M/bin/mkdirs" 2>/dev/null)"
rm -f "$M/bin/mkdir"

[ "$fails" = 0 ] || exit 1
