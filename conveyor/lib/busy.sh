# SPDX-License-Identifier: Apache-2.0
# Why is this machine busy: the processes running now, each given to the card that owns it (`conveyor.sh why`,
# `conveyor.sh work`, the Board's Work now view). Sourced, never run.
# A card owns a process when the process, or the nearest process above it, works in the card's folder under the cards
# folder of any project of the host file's records (its worktree, or a folder beside it named after it, as a review's
# <card>.rv, or a main run's mainrun/<card>, mainrun/<card>.speed and the like): a test runner's worker that works in
# /tmp is the card's through its parents. An open card also owns its own engine process (the pid its worktree record
# names, while it runs and started then), which works in the project's main folder, and so what that process starts
# there. A worktree removed under a process still names it (Linux reads it as
# "<folder> (deleted)"). An open card's process is in its card's live step. The card is open while its records name no end (landed, closed, blocked) and the loop
# that made its worktree runs (as health's gone); else it is closed, and what it still runs is left over.

# The busy line: a process that used at least this share of one core (in percent) over the look is busy.
BUSY_MIN=5

# Every process now, one a line, tab-separated: pid, parent, CPU (percent of one core over the last <seconds>, - with
# none), folder it works in, command. Linux reads /proc twice, <seconds> apart, and
# the folders all at once (find); macOS asks ps (its %CPU, a recent average, whatever <seconds>) and lsof.
busy_table() { # <seconds>
  local a b hz
  if [ -r /proc/self/stat ]; then
    hz=$(getconf CLK_TCK 2>/dev/null) && [ "${hz:-0}" -gt 0 ] || hz=100
    b=$(cat /proc/[0-9]*/stat 2>/dev/null)
    a=''; [ "$1" = 0 ] || { a=$b; sleep "$1"; b=$(cat /proc/[0-9]*/stat 2>/dev/null); }
    { echo @a; [ -z "$a" ] || printf '%s\n' "$a"
      echo @b; printf '%s\n' "$b"
      echo @d; find /proc/[0-9]*/cwd -maxdepth 0 -printf '%h\t%l\n' 2>/dev/null
      echo @p; ps -A -o pid= -o args= 2>/dev/null
    } | awk -v look="$1" -v hz="$hz" '
      /^@/ { s = $0; next }
      s == "@a" || s == "@b" { p = $1; r = $0; i = index(r, " ("); j = length(r); while (j > 0 && substr(r, j, 1) != ")") j--
        c = substr(r, i + 2, j - i - 2); n = split(substr(r, j + 2), f, " ")
        if (s == "@a") { t1[p] = f[12] + f[13]; next }
        t2[p] = f[12] + f[13]; pp[p] = f[2]; cmd[p] = c; next }
      s == "@d" { i = index($0, "\t"); p = substr($0, 7, i - 7); cwd[p] = substr($0, i + 1); next }
      s == "@p" { p = $1; r = $0; sub(/^ *[0-9]+ /, "", r); if (r != "") cmd[p] = r }
      END { for (p in t2) { u = "-"; if (look > 0 && (p in t1)) u = sprintf("%.1f", (t2[p] - t1[p]) * 100 / hz / look)
        x = cmd[p]; gsub(/\t/, " ", x); y = cwd[p]; gsub(/\t/, " ", y); printf "%s\t%s\t%s\t%s\t%s\n", p, pp[p], u, y, x } }'
    return 0
  fi
  { echo @d; lsof -nP -d cwd -Fpn 2>/dev/null
    echo @p; LC_ALL=C ps -A -o pid= -o ppid= -o pcpu= -o args= 2>/dev/null
  } | awk '
    /^@/ { s = $0; next }
    s == "@d" && /^p/ { p = substr($0, 2); next }
    s == "@d" && /^n/ { cwd[p] = substr($0, 2); next }
    s == "@p" { r = $0; sub(/^ *[0-9]+ +[0-9]+ +[0-9.]+ ?/, "", r); gsub(/\t/, " ", r); y = cwd[$1]; gsub(/\t/, " ", y)
      printf "%s\t%s\t%s\t%s\t%s\n", $1, $2, $3, y, r }'
}

# The processes of the table on stdin (busy_table's lines) as one JSON array, each {pid, ppid, cpu (null with no look),
# command, parents (the pids above it, nearest first), card (its owner's id, else null), project (its owner's repo,
# else null)}, read with the projects <records> (busy_recs: [{repo, cards, pids}]).
# The processes of this command (the shell <self> and all under it) are left out.
busy_procs() { # <records> <self>
  jq -Rn --argjson rs "$1" --argjson me "$2" '
    [inputs | split("\t") | select(length >= 5 and (.[0] | test("^[0-9]+$")))
      | {pid: (.[0] | tonumber), ppid: (.[1] | tonumber? // 0), cpu: (.[2] | tonumber? // null), cwd: .[3],
         command: (.[4:] | join(" "))}] as $all
    | ($all | map({key: (.pid | tostring), value: .}) | from_entries) as $by
    | def up: [limit(64; recurse($by[(.ppid | tostring)] // empty; .pid > 1)) | .pid] | .[1:];
      def card: (.pid | tostring) as $p | (.cwd as $w | first($rs[] | .cards as $c | select($w | startswith($c + "/")) | .repo as $r | $w[($c | length) + 1:]
        | split("/") | (if .[0] == "mainrun" then .[1] // "" else .[0] end) | sub(" \\(deleted\\)$"; "") | split(".")[0]
        | select(test("^c[0-9]{8}T[0-9]{6}-([A-Za-z0-9-]*-)?[0-9]+$")) | {card: ., project: $r}))
        // first($rs[] | .repo as $r | (.pids // {})[$p] // empty | {card: ., project: $r});
    [$all[] | . + {parents: up} | select(.pid != $me and (.parents | index($me) | not))
      | ([.] + [.parents[] | $by[tostring] // empty]) as $line
      | (first($line[] | card) // {card: null, project: null}) as $o
      | {pid, ppid, cpu, command, parents, card: $o.card, project: $o.project}]'
}

# The cards <ids...> of the project whose cards folder is <cards> and card records <records file>, as one JSON object
# by id: {issue (null for a main-red fix card, issue 0), step (the live record's, while open), closed}. A card the
# records do not name is closed.
busy_cards() { # <cards> <records file> <id>...
  local id e p t o='{}' s c=$1 rd=$2
  shift 2
  [ $# -gt 0 ] || { echo '{}'; return 0; }
  while IFS=$'\t' read -r id e p t; do
    s=null; [ "$e" = false ] && [ -n "$p" ] && p_alive "$p" "$t" && { s=$(jq -c '.step | strings' "$c/$id.live" 2>/dev/null); s=${s:-null}; e=false; } || e=true
    o=$(jq -c --arg k "$id" --argjson s "$s" --argjson e "$e" '.[$k] = {issue: ($k | capture("-(?<n>[0-9]+)$").n | tonumber | if . == 0 then null else . end), step: $s, closed: $e}' <<<"$o")
  done < <(jq -rn '$ARGS.positional as $ids
      | reduce (inputs | objects | select((.card | type) == "string" and (.card as $c | $ids | index($c)))) as $r ({};
          .[$r.card] |= ((. // {ended: false}) | if ($r.step | IN("landed", "closed", "blocked")) then .ended = true else . end
            | if $r.step == "worktree" and ($r.pid | type) == "number" then .pid = $r.pid | .started = ($r.started // "") else . end))
      | . as $k | $ids[] | [., (if $k[.] then $k[.].ended else true end), ($k[.].pid // ""), ($k[.].started // "")] | @tsv' --args "$@" < "$rd" 2>/dev/null)
  echo "$o"
}

# The engine processes of the open cards of <records file> (a card's last worktree record's pid, while its records name
# no end and that pid runs and started when the record says), as one JSON object {"<pid>": "<card>"}.
busy_pids() { # <records file>
  local id p t o='{}'
  while IFS=$'\t' read -r id p t; do
    p_alive "$p" "$t" || continue
    o=$(jq -c --arg k "$p" --arg c "$id" '.[$k] = $c' <<<"$o")
  done < <(jq -rn 'reduce (inputs | objects | select((.card | type) == "string")) as $r ({};
      .[$r.card] |= ((. // {}) | if ($r.step | IN("landed", "closed", "blocked")) then .ended = true else . end
        | if $r.step == "worktree" and ($r.pid | type) == "number" then .pid = $r.pid | .started = ($r.started // "") else . end))
    | to_entries[] | select(.value.ended != true and .value.pid != null) | [.key, .value.pid, .value.started] | @tsv' 2>/dev/null < "$1")
  echo "$o"
}

# The projects of the host file's records (projects(), lib/machine.sh), this one first, as one JSON array of {repo,
# cards (its cards folder, as the kernel names it), read (its card records), pids (busy_pids)}. Another record's folders are those its
# own commands use (its `conveyor.sh state-dir`, and the cards folder's name kept there); a record whose cards folder
# was never made has no cards, and is left out.
busy_recs() {
  local me o r m e st k c
  me=$(cd "$MAIN" 2>/dev/null && pwd -P) || me=$MAIN
  c=$(cd "$CARDS" 2>/dev/null && pwd -P) || c=$CARDS
  o=$(jq -cn --arg r "$REPO" --arg c "$c" --arg d "$READ" --argjson p "$(busy_pids "$READ")" '[{repo: $r, cards: $c, read: $d, pids: $p}]')
  while IFS=$'\t' read -r r m e; do
    [ "$(cd "$m" 2>/dev/null && pwd -P)" != "$me" ] || continue
    st=$(env -u CONVEYOR_CARDS CONVEYOR_MAIN="$m" bash "$HERE/conveyor.sh" state-dir 2>/dev/null) && k=$(keptcards "$st/cards-folder") \
      && c=$(cd "$(dirname "$m")/$k" 2>/dev/null && pwd -P) || continue
    o=$(jq -c --arg r "$r" --arg c "$c" --arg d "$st/cards.jsonl" --argjson p "$(busy_pids "$st/cards.jsonl")" '. + [{repo: $r, cards: $c, read: $d, pids: $p}]' <<<"$o")
  done < <(projects)
  echo "$o"
}

# The processes of the table on stdin (busy_procs) with their card's facts laid in: step (an open card's live step;
# none for a closed card's or no card's), issue, closed (null for a process no card owns).
# Its project is busy_procs's: the repo of the record whose cards folder holds the card. This command's processes are
# those under its own shell ($$).
busy_read() {
  local p c='{}' recs r i ids
  recs=$(busy_recs) || return 1
  p=$(busy_procs "$recs" "$$") || return 1
  for ((i = 0; i < $(jq length <<<"$recs"); i++)); do
    r=$(jq -c ".[$i]" <<<"$recs")
    mapfile -t ids < <(jq -r --arg r "$(jq -r .repo <<<"$r")" '[.[] | select(.project == $r) | .card] | unique[]' <<<"$p")
    c=$(jq -c --argjson n "$(busy_cards "$(jq -r .cards <<<"$r")" "$(jq -r .read <<<"$r")" "${ids[@]}")" '. + $n' <<<"$c") || return 1
  done
  jq -c --argjson c "$c" 'map(. as $p | ($c[$p.card // ""] // null) as $k
    | . + {issue: $k.issue, closed: $k.closed, step: (if $k == null or $k.closed then null else $k.step end)})' <<<"$p"
}

# conveyor.sh why <pid | name> [--json], of the table on stdin (busy_table 0): the process <pid>, or every process
# whose program is <name>, with its parents, and the card, step and project it is of, or that no card owns it; a
# closed card's process with the command that stops what that card left. Exit 1 when no process is so.
busy_why() { # <pid | name> [--json]
  local all m
  all=$(busy_read) || return 1
  m=$(jq -c --arg w "$1" '. as $all | ($all | map({key: (.pid | tostring), value: .}) | from_entries) as $by
    | [.[] | select(if ($w | test("^[0-9]+$")) then .pid == ($w | tonumber) else (.command | split(" ")[0] | split("/")[-1]) == $w end)]
    | map(.card as $k | . + {parents: [.parents[] | {pid: ., command: ($by[tostring].command // "")}],
        stop: (if .closed == true then "kill \([$all[] | select(.card == $k) | .pid] | sort | map(tostring) | join(" "))" else null end)} | del(.cpu))' <<<"$all") || return 1
  [ "$m" != '[]' ] || { echo "conveyor: no process is $1" >&2; return 1; }
  [ "${2:-}" != --json ] || { echo "$m"; return 0; }
  jq -r '.[] | "\(.pid) \(.command[:120])",
    "  parents: \(if .parents == [] then "none" else [.parents[] | "\(.pid) \(.command | split(" ")[0] | split("/")[-1])"] | join(" < ") end)",
    "  " + (if .card == null then "no card owns it"
      else "card \(.card)" + (if .issue then " (issue #\(.issue))" else "" end) + " of project \(.project)"
        + (if .closed then ", which is closed: it is left over; stop what the card left with: \(.stop)"
           else ", in its \(.step // "unknown") step" end) end)' <<<"$m"
}

# conveyor.sh work [--json], of the table on stdin (busy_table 1: a look of a second): the busy processes (BUSY_MIN),
# by card and step, the heaviest CPU first (each group by its processes' sum), and then the busy processes no card
# owns. A closed card's group is left over, and names the command that stops every process of the card.
busy_work() { # [--json]
  local all w
  all=$(busy_read) || return 1
  w=$(jq -c --argjson min "$BUSY_MIN" '. as $all | map(select(.cpu != null and .cpu >= $min) | del(.parents)) as $b
    | {groups: ([$b[] | select(.card)] | group_by([.card, .step]) | map({card: .[0].card, issue: .[0].issue, project: .[0].project,
        step: .[0].step, closed: .[0].closed, cpu: (map(.cpu) | add * 10 | round / 10),
        stop: (.[0].card as $k | if .[0].closed then "kill \([$all[] | select(.card == $k) | .pid] | sort | map(tostring) | join(" "))" else null end),
        processes: (sort_by(-.cpu) | map({pid, cpu, command}))}) | sort_by(-.cpu)),
       other: ([$b[] | select(.card == null) | {pid, cpu, command}] | sort_by(-.cpu))}' <<<"$all") || return 1
  [ "${1:-}" != --json ] || { echo "$w"; return 0; }
  jq -r --argjson min "$BUSY_MIN" '"conveyor: busy now (\($min)% of one core or more over the last second), heaviest first",
    (.groups[] | "card \(.card)" + (if .issue then " (issue #\(.issue))" else "" end) + " of \(.project), "
        + (if .closed then "closed: left over" else "\(.step // "unknown") step" end) + ": \(.cpu)%",
      (.processes[] | "  \(.cpu)%  \(.pid)  \(.command[:120])"),
      (if .stop then "  stop them: \(.stop)" else empty end)),
    (if .other != [] then "no card owns:", (.other[] | "  \(.cpu)%  \(.pid)  \(.command[:120])") else empty end),
    (if .groups == [] and .other == [] then "nothing is busy" else empty end)' <<<"$w"
}
