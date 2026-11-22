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
T=$(mktemp -d) || exit 1
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
# a checkout per project. Each case is a machine of its own.
machine() { # <case>
  M=$T/$1; H=$M/home
  mkdir -p "$H/.config/conveyor" "$M/clone/conveyor/lib" "$M/bakery" "$M/gadgetlab" "$M/bin"
  cp "$DIR/../conveyor/lib/portable.sh" "$M/clone/conveyor/lib/portable.sh" # the fetch's cut takes its PATH from it
  printf '%s\n' '#!/usr/bin/env bash' '[ "$1" = snapshot ] || exit 2' \
    "awk -F'\\t' -v r=\"\${CONVEYOR_MAIN##*/}\" '\$1 == r { sub(/^[^\\t]*\\t/, \"\"); print }' '$T/two.txt'" > "$M/clone/conveyor/conveyor.sh"
}
hostfile() { jq -n "$@" > "$H/.config/conveyor/host.json"; }
fetch() { # <checkout> [<arg>]: the fetch's output, the home folder shown as /r/HOME
  (cd "$1" && unset CONVEYOR_FOREMAN_DIR && HOME=$H XDG_CONFIG_HOME=$H/.config PATH=$M/bin:$PATH bash "$FETCH" "${@:2}") | sed "s|$H|/r/HOME|g"
}

# D2: a host file with two projects, neither the plugin's own, read in the first one's checkout.
machine two
hostfile --arg c "$M/clone" --arg b "$M/bakery" --arg g "$M/gadgetlab" \
  '{host: "lab", ssh: "lab", main: $c, records: [{repo: "bakery", main: $b}, {repo: "gadgetlab", main: $g}]}'
same 'two projects: their snapshots in the host file order, read here, as the fixture /units draws' "$WANT" "$(fetch "$M/bakery")"
# Bug: the first record was taken for the session's own project, so a session in gadgetlab showed bakery's cards
# with no name and looked for its Fast lane's card among bakery's. The own project is the record whose main is here.
same 'a session in the second project names that project its own' "$(sed '1s/\tbakery$/\tgadgetlab/' <<<"$WANT")" "$(fetch "$M/gadgetlab")"

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
same 'the lanes from the host file' "$(printf 'paths\t%s/research\t%s\tbakery\nfast\tok\tlane-12\t1\t0\tBread oven timer\nhost\t\tfeed\t0' "$RH" "$RH")" \
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
echo '{}' > "$FD/settings.json"
same 'a set-up Foreman whose role no session holds still prints its line' \
  "$(printf 'foreman\t\t%s\t%s\ts1\t0\t%s\t\tdown: the session'"'"'s process 77 has ended' "$WP" "$A" "$A")" "$(foreman)"
# Issue 139: the plugin problems the Foreman noted (stop.sh writes one "- " line each) are counted, with the file, so
# /units can say so; the file's heading is no problem. Bug it catches: a noted problem /units never showed.
printf '# Plugin problems\n\n- 2026-11-16T10:00:00Z · card #7 · a · evidence: -\n- 2026-11-16T11:00:00Z · card - · b · evidence: -\n' > "$FD/plugin-bugs.md"
same 'the plugin problems noted: how many, and the file' "$(printf 'pluginbugs\t2\t%s' "$FD/plugin-bugs.md")" "$(fetch "$M/bakery" feed | grep '^pluginbugs')"
# Issue 176: while the test map is made, the progress the engine writes beside it (conveyor/lib/testmap.sh) is read,
# feed or not; a checkout with no project settings (the machines above) prints no testmap line. Bug it catches: /units
# never showed a map's run, so a setup or refresh that ran for many minutes looked like nothing.
mkdir -p "$M/bakery/.conveyor" && echo '{}' > "$M/bakery/.conveyor/project.json"
echo "{\"pid\": $$, \"started\": 1700000000, \"done\": 3, \"of\": 8}" > "$M/bakery/.conveyor/test-map.run.json"
same 'the test map being made: its files run of how many, and its start' \
  "$(printf 'testmap\t{"state":"running","done":3,"of":8,"started":1700000000}')" "$(fetch "$M/bakery" feed | grep '^testmap')"
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
# with the feed, the map alone is asked over ssh. Bug it catches: /units showed this machine's map, which no run on the
# build machine makes or refreshes, so it read "being made" or "not made yet" forever; or, with the Board's live feed
# fresh, it showed no map at all.
machine buildmap
printf '%s\n' '#!/usr/bin/env bash' 'while [ "$1" = -o ]; do shift 2; done' 'bash -c "$2"' > "$M/bin/ssh" && chmod +x "$M/bin/ssh"
# The stub engine's testmap names the checkout it was asked of; its snapshot is the fixture's, as above.
printf '%s\n' '#!/usr/bin/env bash' '[ "$1" != testmap ] || { echo "{\"state\":\"made\",\"of\":\"$CONVEYOR_MAIN\"}"; exit 0; }' \
  '[ "$1" = snapshot ] || exit 2' "awk -F'\\t' -v r=\"\${CONVEYOR_MAIN##*/}\" '\$1 == r { sub(/^[^\\t]*\\t/, \"\"); print }' '$T/two.txt'" > "$M/clone/conveyor/conveyor.sh"
mkdir -p "$M/dev/bakery/.conveyor" && echo '{}' > "$M/dev/bakery/.conveyor/project.json"
echo "{\"pid\": $$, \"started\": 1700000000, \"done\": 3, \"of\": 8}" > "$M/dev/bakery/.conveyor/test-map.run.json"
hostfile --arg c "$M/clone" --arg b "$M/bakery" --arg g "$M/gadgetlab" \
  '{host: "lab", ssh: "owner@lab", main: $c, records: [{repo: "gadgetlab", main: $g}, {repo: "bakery", main: $b}]}'
got=$(fetch "$M/dev/bakery")
same 'a build machine: its map, of the record named as this checkout, before the host line' \
  "$(printf 'testmap\t{"state":"made","of":"%s"}\nhost\tlab\tssh\t0' "$M/bakery")" "$(grep -E '^(testmap|host)' <<<"$got")"
same 'a build machine: every record still has its snapshot' 'gadgetlab bakery' "$(sed -n '/^host/,$p' <<<"$got" | sed 1d | cut -f1 | tr '\n' ' ' | sed 's/ $//')"
same 'a build machine with the feed: its map still, and no snapshots' \
  "$(printf 'testmap\t{"state":"made","of":"%s"}\nhost\t\tfeed\t0' "$M/bakery")" "$(fetch "$M/dev/bakery" feed | grep -E '^(testmap|host|gadgetlab|bakery)')"

# The short check (issue 1033): `stamp` prints one checksum a record, of its state folder's cards.jsonl, control.json
# and queue, in one command (one ssh call for every record); `fresh <repo>` asks that record for a snapshot built now.
# The stub engine names each checkout's state folder, and its snapshot is the kept one (health state "kept") unless
# --fresh, then the last line of cards.jsonl as its health. Bugs it catches: a card started showed only at the next minute's fetch, and then from a
# kept snapshot older than it; a check asked the host once a record, or moved for a record nothing changed in.
machine stamp
printf '%s\n' '#!/usr/bin/env bash' 'case $1 in' 'state-dir) echo "$CONVEYOR_MAIN/state" ;;' \
  'snapshot) if [ "${2-}" = --fresh ]; then tail -n 1 "$CONVEYOR_MAIN/state/cards.jsonl" | jq -c "{health: .}"; else echo "{\"health\":{\"state\":\"kept\"}}"; fi ;;' '*) exit 2 ;;' 'esac' > "$M/clone/conveyor/conveyor.sh"
printf '%s\n' '#!/usr/bin/env bash' 'echo x >> "$(dirname "$0")/calls"' 'while [ "$1" = -o ]; do shift 2; done' 'bash -c "$2"' > "$M/bin/ssh" && chmod +x "$M/bin/ssh"
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

# Bug (issue 1287): a snapshot printed whole, with the Tests page's history (tests, testActions) and every declined line,
# grew past what the fetch could read in time, and past the cap, though the pane draws none of it. The stub engine prints
# a snapshot with a large tests part; the fetch prints only the parts the pane draws, the judge's declined lines cut to
# id, who and time, and open cut to its two lists.
machine cut
printf '%s\n' '#!/usr/bin/env bash' '[ "$1" = snapshot ] || exit 2' \
  "jq -nc '{health: {state: \"ok\"}, belt: [], queue: {next: []}, cost: {today: 1}, snapshotAt: \"t\", tests: [range(0; 3000) | {file: \"f\\(.)\", log: (\"x\" * 1000)}], testActions: [range(0; 5)], declined: [{id: \"a\", by: \"judge\", time: \"t1\", why: \"long\"}, {id: \"b\", by: \"owner\", time: \"t2\"}], declinedRest: [], open: {umbrellas: [{issue: 1}], held: [], issues: [range(0; 50)]}}'" > "$M/clone/conveyor/conveyor.sh"
hostfile --arg c "$M/clone" --arg b "$M/bakery" '{host: "lab", ssh: "lab", main: $c, records: [{repo: "bakery", main: $b}]}'
got=$(fetch "$M/bakery" | sed -n '/^host/,$p' | sed 1d)
same 'the snapshot the host fallback prints holds only what the pane draws, whatever the Tests page holds' \
  'bakery	{"health":{"state":"ok"},"belt":[],"queue":{"next":[]},"cost":{"today":1},"snapshotAt":"t","declined":[{"id":"a","by":"judge","time":"t1"}],"declinedRest":[],"open":{"umbrellas":[{"issue":1}],"held":[]}}' "$got"
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

[ "$fails" = 0 ] || exit 1
