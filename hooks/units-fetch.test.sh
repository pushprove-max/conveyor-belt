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
fails=0
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
  mkdir -p "$H/.config/conveyor" "$M/clone/conveyor" "$M/bakery" "$M/gadgetlab" "$M/bin"
  printf '%s\n' '#!/usr/bin/env bash' '[ "$1" = snapshot ] || exit 2' \
    "awk -F'\\t' -v r=\"\${CONVEYOR_MAIN##*/}\" '\$1 == r { sub(/^[^\\t]*\\t/, \"\"); print }' '$T/two.txt'" > "$M/clone/conveyor/conveyor.sh"
}
hostfile() { jq -n "$@" > "$H/.config/conveyor/host.json"; }
fetch() { # <checkout> [<arg>]: the fetch's output, the home folder shown as /r/HOME
  (cd "$1" && HOME=$H XDG_CONFIG_HOME=$H/.config PATH=$M/bin:$PATH bash "$FETCH" "${@:2}") | sed "s|$H|/r/HOME|g"
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

# The same with no ssh target: nothing is asked, and the board says why.
machine nossh
hostfile --arg c "$M/clone" --arg b "$M/bakery" '{host: "lab", main: $c, records: [{repo: "bakery", main: $b}]}'
mkdir -p "$M/elsewhere"
same 'no ssh target: nossh' $'paths\t\t/r/HOME\t\nfast\tnorecord\nhost\tlab\tnossh\t0' "$(fetch "$M/elsewhere")"

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

[ "$fails" = 0 ] || exit 1
