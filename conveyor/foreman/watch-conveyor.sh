#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# watch-conveyor.sh [--once | --status [<project>]] -- the Foreman's Conveyor watcher, run by waiter.sh. Once a minute it asks the
# Foreman's own record, or each record of its group (lib.sh mine), never another project's, for `conveyor.sh
# snapshot` (lib.sh ask) and, on any NEW problem, puts one wake in pending and
# exits. The problems, each a record's own:
#   a card waiting on the owner's yes       an issue waiting on the owner's yes before its build (health's before)
#   a card blocked
#   a card stuck (health's stuck: no new step and no output, its process gone, a wait on other cards past the
#     limit, with the cards it waited on, or a test case that hangs, by name); one whose step the engine ended
#     for no progress and runs once more (did) is a new problem, and says so ("ended and retried"); a second stall
#     blocks the card, and its blocked alert says so; each only once two polls in a row, at least a poll apart, list it
#   a card that has waited for main to change, or on another card, for the pack's foreman.waitWake minutes (default
#     10): it names the card, what it waits on and that card's step and last action (for main, each main-red fix card
#     open or blocked); once per wait, and "still waiting" after each further waitWake minutes of it
#   the record unreachable: no snapshot for 2 minutes (never one failed poll)
#   an awaited issue landed: $FD/await-<repo>.txt lists issue numbers, one per line, of the record <repo>, so a
#     group's Foreman claimed in another checkout awaits the same issues of the same projects; one whose card has
#     pushed wakes once, naming the commit it landed as. The Foreman only appends to it: what was dropped is counted in await-done-<repo>.txt
#     ("<issue> <its lines in await-<repo>.txt then>"), so a line appended later awaits it again
#   a whole-suite run (a release's or the full test's, snapshot suites) that ended: its result, commit and failed cases
#   a push that failed its check (health's pushError.kind check), at once and again for each commit it fails on: the
#     loop does not push again until main moves
#   a card's test step that refused a full run of its tests (health's refused: the engine's tests()), once a test line
#   every other entry of the Board's Needs you: .claude/scripts/dashboard_needs.json is the one list of its kinds,
#     which the Board reads too, each with the snapshot field it is read from (the whole test failing on main, an engine
#     update not taken, test issues held, a pipeline change held for the owner, a dependency that cannot be read,
#     and any kind added to the list later, under its kind). A held pipeline change's line names it, its parent and
#     its finding: "pipeline change held: #615 (follow-up of #597): <finding>"
#   no loop running, a push failing for over 10 minutes or listed under the Board's blocked cards (needsYou.blocked:
#   it failed twice), gh signed out, a control record the loop cannot read, a
#   dependency cycle among open issues, and Conveyor idle (nothing on the belt and nothing to pick) on two polls in a row
# Every wake names every item. Its first line lists every issue number by kind, per project:
#   Conveyor: shop: needs the owner's yes: #12 #15; blocked: #7 | site: needs the owner's yes: #19
# then one line per item, each cut alone if it must be; the wake as a whole is never cut.
# A problem reported is not reported again until it clears and comes back: conveyor-reported.txt holds the keys,
# "<repo>/<key>", of the reported problems still there, so a restart repeats nothing. While a record gives no
# snapshot, its reported problems stay reported.
# A card that only moves on the belt (build to review, review to tests) needs no one and wakes nothing.
# --status prints the records' state for the Foreman to read, and reports nothing as seen (STATUS, below).
# For tests: CONVEYOR_FOREMAN_ASK (lib.sh), CONVEYOR_FOREMAN_NOW (the clock, epoch seconds), --once (one poll: exit 0
# with a wake put, 1 with nothing new).
set -u
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh" || exit 1
SEEN=$FD/conveyor-reported.txt
POLL=60 DOWN_S=120 PUSH_S=600
# The kinds of the Board's Needs you, the list the Board reads too: one that does not read stops the watcher here,
# never as a record read as unreachable.
KINDS=$FHERE/../../.claude/scripts/dashboard_needs.json
jq -e 'arrays | all(.[]; (.kind | strings) and (.from | arrays))' "$KINDS" >/dev/null || { echo "watch-conveyor: $KINDS does not read as the list of Needs you kinds" >&2; exit 1; }
RECS=$(mine) || exit 1

# A whole-suite run of the snapshot's suites (a release's or the full test's) on one line: under way, its commit, how
# long it has run, the cases done of the cases selected (the total when its runner gives it) and failed; ended, its result and commit; either way the failed cases by name.
# The names are the cases its runner named as ended (fulltest.sh suiteprog()): an engine case by its own name, never
# its file, so the line says cases, not files.
SUITE='def took: if . < 3600 then "\(. / 60 | floor)m" else "\(. / 3600 | floor)h\(. % 3600 / 60 | floor)m" end;
  def suiteline($now): (if .kind == "release" then "release \(.version // "")" else "full test" end) as $k
    | (.sha // "" | if . == "" then "no commit yet" else .[0:12] end) as $c
    | ([.cases | arrays | .[] | tostring] | if length > 20 then "\(.[:20] | join(", ")) and \(length - 20) more" else join(", ") end) as $f
    | if .ended == null then "\($k) running on \($c) for \((.since | fromdate? | $now - .) // null | if . == null then "?" else took end): \(.done // 0)\(if .of == null then "" else " of \(.of)" end) cases done, \(.failed // 0) failed\(if $f == "" then "" else ": \($f)" end)"
      else "\($k) \(.state // "ended") on \($c) at \(.ended)\(if $f == "" then "" else "; failed cases: \($f)" end)" end;'
# The issues of a snapshot, or of its history ($hist: `conveyor.sh history`, null when not read), whose card pushed:
# landed and not in health's unpushed, or in pushedCards. The snapshot holds only the newest of both lists (#544:
# with 110 pushed today an awaited issue among the oldest was in neither, and never woke the Foreman).
PUSHED='def pushed($hist): [.health.unpushed | arrays | .[] | objects | .card] as $unpushed
  | [(., ($hist | objects)) | (.metrics.cards | arrays | .[] | objects | select(.state == "landed" and (.card | IN($unpushed[]) | not)) | .issue | numbers),
     (.pushedCards | arrays | .[] | objects | .issue | numbers)];'
# A card by its issue, "#n"; a main-red fix card, which has no issue (issue 0), by its name, "Main is red (<commit>)"
# (health and the snapshot give it: rows.jq).
REF='def ref: (.name | strings) // "#\(.issue)";'
# A snapshot's problems, one per line: <key> TAB <kind> TAB <issue numbers, "#n" by spaces> TAB <text>. Fails for
# anything but a snapshot holding a health record. idle is a candidate here: record() reports it on its second poll.
# An awaited issue that landed names its commit (the snapshot's or the history's landed line of it); a whole-suite run
# that ended (snapshot suites) is one item, its line as the status command prints it, the failed cases named.
PROBLEMS=$SUITE$PUSHED$REF'def one: tostring | gsub("\\s+"; " ") | .[0:240];
  (type == "object" and .belt == [] and (.queue.next // null) == []) as $idle
  | pushed($hist[0]) as $pushed
  | . as $snap
  # The push the Board lists under blocked (snapshot.sh: a push that failed twice), which health holds only as pushFailingSince.
  | any(.needsYou | objects | .blocked | arrays | .[]; objects | .push == true) as $pushheld
  | .health
  | if type == "object" and ([.loop, .gh] | all(type == "boolean")) and ([.blocked, .waiting, .stuck] | all(type == "array" and all(type == "object")))
    and (.time | fromdate | type == "number") and (.pushFailingSince | type == "null" or (fromdate | type == "number"))
  then . else error("not a health record") end
  | (.waiting[] | ["waiting:\(.card)", "needs the owner'"'"'s yes", ref, "\(ref) needs the owner'"'"'s yes since \(.since): \(.reason | one)"]),
    (.before | arrays | .[] | objects | select(.issue | numbers)
      | ["before:\(.issue)", "needs the owner'"'"'s yes", "#\(.issue)", "#\(.issue) needs the owner'"'"'s yes before its build since \(.since): \(.title | one)"]),
    (.blocked[] | ["blocked:\(.card)", "blocked", ref, "\(ref) is blocked since \(.since): \(.reason | one)"]),
    (.stuck[] | if .did then ["stuck:\(.card):\(.did)", "stuck", ref, "\(ref) is stuck: no progress since \(.since) at \(.step); the engine \(.did) it"]
      else ["stuck:\(.card)", "stuck", ref, "\(ref) is stuck: " + (
      if (.waitedOn | type) == "array" then "it has waited on other cards for \(.waitedMin) minutes in all (\([.waitedOn[] | objects | ref] | join(", ")))"
      elif (.cases | type) == "array" then "its test step has had \(.cases | map(tostring) | join(", ") | one) running since \(.since)"
      else "no new step and no output since \(.since) (last step: \(.step))" end)] end),
    ($await[] | select(.[0] | IN($pushed[])) | .[0] as $i
      | (first($snap, ($hist[0] | objects) | .landed | arrays | .[] | objects | select(.issue == $i) | .sha | strings | select(. != "")) // "") as $sha
      | ["landed:\(.[0]):\(.[1])", "landed", "#\(.[0])", "#\(.[0]) landed\(if $sha == "" then "" else " as \($sha[0:12])" end): your step is due"]),
    ($snap.suites | arrays | .[] | objects | select(.ended != null)
      | ["suite:\(.kind | tostring | gsub("\\s"; "-")):\(.ended)", "suite ended", "", suiteline($now) | gsub("\\s+"; " ")]),
    (select(.loop | not) | ["noloop", "no loop", "", "no loop is running"]),
    (select(.pushFailingSince != null) | .pushError as $e
      | if ($e | type) == "object" and $e.kind == "check" then
          ["push:\($e.sha)", "push blocked", ($e.name | strings) // ($e.issue | numbers | select(. > 0) | "#\(.)") // "",
           "push blocked: \($e.check // "a check" | one) failed after \(($e.name | strings) // ($e.issue | numbers | select(. > 0) | "#\(.)") // ($e.card // "the last landing" | one)); it will not pass on a retry"]
        elif $pushheld or (.time | fromdate) - (.pushFailingSince | fromdate) > $push then
          ["push", "push failing", "", "the push has failed since \(.pushFailingSince): \(.pushError.reason // "" | one)"]
        else empty end),
    (.refused | arrays | .[] | objects | ["refused:\(.card):\(.since)", "full test run refused", ref, "\(ref): the test step \(.reason | one)"]),
    # A card records line the check set aside (health quarantined, conveyor/lib/views.sh check()).
    (.quarantined | arrays | .[] | objects | ["quarantined:\(.line):\(.time)", "record set aside", "",
      "the card records line \(.line) is set aside in quarantined.jsonl: the record check refused its field \(.field | one)"]),
    (select(.gh | not) | ["gh", "gh signed out", "", "gh is signed out"]),
    (select(.state == "control record unreadable") | ["control", "picks nothing", "", "the loop picks nothing: \(.reason // "the control record does not read" | one)"]),
    (.cycles | arrays | .[] | arrays | map(tostring) | ["cycle:\(join("-"))", "dependency cycle", (map("#" + .) | join(" ")),
      "issues \(map("#" + .) | join(", ")) depend on each other: none of them will be picked"]),
    # A card that has waited $wake minutes (the pack'"'"'s foreman.waitWake, the snapshot'"'"'s waitWake: read on the belt'"'"'s
    # host, as a remote belt'"'"'s pack is not on this machine; 10 when it gives none) on another card (health waitingOnCard) or
    # for main to change (its live action, testrun.sh mainwait(); the snapshot'"'"'s belt live.at is when that wait
    # began): what it waits on, with that card'"'"'s step and last action, or, for main, each main-red fix card open or
    # blocked. Its key holds the wait'"'"'s start and how many times $wake it has lasted, so each wait wakes once, and
    # again ("still waiting") after each further $wake minutes.
    (.blocked as $hb | (($snap.waitWake | numbers | select(. >= 1)) // 10) as $wake
      | def about($h): ($h | ref) as $r | ([$snap.belt | arrays | .[] | objects | select(.card == $h.card)] | first) as $b
          | ([$hb[] | select(.card == $h.card)] | first) as $x
          | if $b then "\($r) (at \($b.step), last action: \($b.live.action // "none"))"
            elif $x then "\($r) (blocked: \($x.reason))" else "\($r) (\($h.state // "gone"))" end;
      ([$snap.belt | arrays | .[] | objects | select((.name | strings) and (.landed | not)) | about(.)]
        + [$hb[] | select(.name | strings) | about(.)]
        | if . == [] then "no main-red fix card is open" else "main-red fix card " + join(", ") end) as $reds
      | ((.waitingOnCard | arrays | .[] | objects | {c: ., since, on: about(.waitsOn | objects)}),
         ($snap.belt | arrays | .[] | objects | select(.live.action | strings | startswith("waiting for main to change"))
           | {c: ., since: .live.at, on: "main to change (\(.live.action | ltrimstr("waiting for main to change: "))); \($reds)"}))
      | (.since | strings | fromdate?) as $t | (($now - $t) / 60 | floor) as $m | ($m / $wake | floor) as $n | select($n >= 1)
      | (.c | ref) as $r
      | ["wait:\(.c.card):\(.since):\($n)", "card waiting", $r,
          (if $n == 1 then "\($r) has waited \($m) minutes on " else "\($r) is still waiting, \($m) minutes now, on " end) + .on | gsub("\\s+"; " ") | .[0:600]]),
    # Every other kind of Needs you on the Board, from the list the Board reads too (.claude/scripts/dashboard_needs.json), each
    # read from the snapshot field the list names: waiting, before and blocked are read from health, above (the push
    # the Board lists under blocked wakes as "push failing"). A kind added to the list later wakes under its name.
    # Each line is cut alone (one).
    ($kinds[0][] | objects | select(.kind | IN("waiting", "before", "blocked") | not) | (.kind | one) as $k | .from as $from
      | $snap | (try getpath($from) catch null) | (if type == "array" then .[] else . end) | objects
      | ((.issue | numbers | "#\(.)") // "") as $n
      | ([.issue, .ref, .commit, .time, .card] | map(select(. != null) | one) | join(":") | if . == "" then "" else ":" + . end) as $id
      | if $k == "pipeline" then ["pipeline:\(.issue)", "pipeline change held", $n,
          "pipeline change held: \($n)\((.parent | numbers | " (follow-up of #\(.))") // ""): \(.title // "")" | one]
        elif $k == "farDeps" then ["farDeps\($id)", "dependency unreadable", $n, "\($n) waits on \(.ref // "") in another repository, which cannot be read: \(.reason // "")" | one]
        elif $k == "engines" then ["engines\($id)", "engine update not taken", "", "the plugin commit \(.commit // "") was not taken: \(.reason // "")" | one]
        elif $k == "testRules" then ["testRules\($id)", "test issues held", "", "the test rules matched \(.matched) files, over the cap of \(.cap) a day, so they filed none" | one]
        elif $k == "tests" then ["tests:\(.issue)", "tests failing on main", $n,
          "the whole test fails on main (\(if $n == "" then "no issue filed" else $n end)): \(.cases | if type == "array" then map(tostring) | join(", ") else "no case named" end)" | one]
        else ["\($k)\(if $id == "" then ":" + (tojson | one) else $id end)", $k, $n, "\($k): \($n) \(.title // .reason // tojson)" | one] end),
    (select($idle) | ["idle", "idle", "", "Conveyor is idle: nothing in flight and nothing to pick"])
  | join("\t")'

# --status [<project>] (`conveyor.sh foreman status`): each record's state now as short plain text, read from one
# snapshot, with no wake put and nothing marked reported: the belt (its count, and while the loop runs its cards
# building against the cap and those waiting on another card, which that count leaves out; then a card a line: issue, or a main-red fix card's name, step, time in step, title cut to 60 characters), the
# cards waiting on other issues and the held issues as issue numbers, the whole-suite run under way (else the last one
# that ended), then every problem a wake names, the push failing at once, the suite that ended left out (its line is
# above), each "needs you: <text>". <project> names one record of mine; with none, every one of them.
STATUS=$SUITE$REF'def num: if type == "number" then "#\(.)" else tostring end;
  "\($repo): \(.belt | if type == "array" then length else 0 end) on the belt"
    + ((.health | objects | select((.building | type) == "number" and (.builderCap | type) == "number")
      | "; building \(.building) of the cap \(.builderCap)\(if (.waitingCount // 0) > 0 then ", \(.waitingCount) waiting not counted" else "" end)") // ""),
  (.belt | arrays | .[] | objects | "  \(ref) \(.step)\((.waitsOn | objects | select(.issue | numbers) | " on \(ref)") // "")"
    + " \((.stepAt | fromdate? | $now - .) // null | if . == null then "?" else took end) \(.title // "" | tostring | gsub("\\s+"; " ") | .[0:60] | sub(" $"; ""))"),
  (.queue.waiting | arrays | select(length > 0) | "waiting: " + (map(objects | "\(.issue | num) on \(.waitsFor | arrays | map(num) | join(" "))") | join(", "))),
  (.open.held | arrays | select(length > 0) | "held: " + (map(objects | .issue | num) | join(" "))),
  ([.suites | arrays | .[] | objects] as $s | ($s | map(select(.ended == null))) as $run
    | if $run != [] then $run[] | suiteline($now)
      else $s | map(select(.ended != null)) | max_by(.ended) | objects | "last " + suiteline($now) end)'
if [ "${1:-}" = --status ]; then
  now=${CONVEYOR_FOREMAN_NOW:-$(date +%s)} n=0
  errf=$(mktemp) || exit 1; trap 'rm -f "$errf"' EXIT
  while IFS=$'\t' read -r repo main; do
    [ -z "${2:-}" ] || [ "$repo" = "$2" ] || continue
    n=$((n + 1))
    if ! rec=$(ask "$repo" "$main" snapshot 2>"$errf") || ! jq -e objects <<<"$rec" >/dev/null 2>&1; then
      echo "$repo: no snapshot ($(tr -s '[:space:]' ' ' < "$errf" | tail -c 200))"; continue
    fi
    jq -r --arg repo "$repo" --argjson now "$now" "$STATUS" <<<"$rec" 2>/dev/null || echo "$repo: the snapshot's belt does not read"
    jq -r --argjson push -1 --argjson now "$now" --argjson await '[]' --argjson hist '[null]' --slurpfile kinds "$KINDS" "$PROBLEMS" <<<"$rec" 2>/dev/null \
      | awk -F'\t' '$2 != "suite ended" { print "needs you: " $4 }'
    [ "${PIPESTATUS[0]}" = 0 ] || echo "needs you: unknown, the snapshot holds no health record"
  done <<<"$RECS"
  [ "$n" -gt 0 ] || { echo "foreman status: $2 is none of this Foreman's projects ($(cut -f1 <<<"$RECS" | paste -sd' ' -))" >&2; exit 2; }
  exit 0
fi

mkdir -p "$FD" && touch "$SEEN" || exit 1
while IFS=$'\t' read -r r _; do touch "$FD/await-$r.txt" "$FD/await-done-$r.txt" || exit 1; done <<<"$RECS"

# One record's problems now, each line prefixed with its repo: <repo> TAB <key> TAB <kind> TAB <issues> TAB <text>.
record() { # <repo> <main> <now> <await>
  local repo=$1 now=$3 rec cur first last err held
  local down=$FD/conveyor-down-$repo.txt idle=$FD/conveyor-idle-$repo.txt stuckf=$FD/conveyor-stuck-$repo.txt errf=$FD/conveyor-watch-$repo.err
  local histf=$FD/conveyor-history-$repo.json
  # The history is asked for only when an awaited issue is not pushed by the snapshot alone; one that does not read
  # is left out (null), and the next poll asks again. It goes to jq in a file: a busy day's history is over the
  # 128 KB a single argument may hold (#544).
  if rec=$(ask "$repo" "$2" snapshot 2>"$errf") \
    && { jq -e --argjson await "$4" "${PUSHED}"'pushed(null) as $p | any($await[]; .[0] | IN($p[]) | not)' <<<"$rec" >/dev/null 2>&1 \
      && ask "$repo" "$2" history 2>>"$errf" | jq -ce objects > "$histf" 2>>"$errf" || echo null > "$histf"; } \
    && cur=$(jq -r --argjson push "$PUSH_S" --argjson now "$now" --argjson await "$4" --slurpfile hist "$histf" --slurpfile kinds "$KINDS" "$PROBLEMS" <<<"$rec" 2>>"$errf"); then
    rm -f "$down"
    if ! grep -q $'^idle\t' <<<"$cur"; then rm -f "$idle"
    elif [ ! -e "$idle" ]; then touch "$idle"; cur=$(grep -v $'^idle\t' <<<"$cur"); fi
    # A stuck card is a problem only when two snapshots in a row, at least a poll apart, list it: one reading can
    # fall between two lines of a step that goes on. $stuckf holds each stuck key of the last snapshot and when a
    # snapshot first listed it ("<key> TAB <epoch>"); a key the snapshot does not list is dropped from it. When that
    # file cannot be written, the stuck cards are reported at once.
    if touch "$stuckf" && : > "$stuckf.tmp" && held=$(awk -F'\t' -v now="$now" -v poll="$POLL" -v f="$stuckf" '
      FILENAME == f { t[$1] = $2; next }
      $1 ~ /^stuck:/ { s = ($1 in t) ? t[$1] : now; print $1 "\t" s > (f ".tmp"); if (now - s < poll) next }
      { print }' "$stuckf" - <<<"$cur") && mv "$stuckf.tmp" "$stuckf"; then cur=$held; fi
  else
    # A failed poll breaks a run of idle polls. A gap of more than three polls since the last failed one is a new
    # outage, timed from now.
    grep -qxF "$repo/idle" "$SEEN" || rm -f "$idle"
    read -r first last 2>/dev/null < "$down" || first=
    [[ $first =~ ^[0-9]+$ ]] && [[ $last =~ ^[0-9]+$ ]] && [ $((now - last)) -le $((POLL * 3)) ] || first=$now
    echo "$first $now" > "$down"
    # Its reported keys stay reported (no text: a key already reported is never printed again).
    cur=$(awk -v p="$repo/" 'index($0, p) == 1 && $0 != p "unreachable" { print substr($0, length(p) + 1) "\t\t\t" }' "$SEEN")
    err=$(tr -s '[:space:]' ' ' < "$errf" | tail -c 200)
    # The install this watcher runs from, removed under it, fails every poll on its own missing files: the line names
    # that install and the fix, not the file it missed.
    [ -f "$KINDS" ] || err="the Conveyor install ${FHERE%/conveyor/foreman} the Foreman's watcher runs from is gone; run /conveyor-belt:setup in $2 to install the project's engine again"
    [ $((now - first)) -lt "$DOWN_S" ] || cur+=$'\n'"unreachable"$'\t'"unreachable"$'\t\t'"no snapshot for $(((now - first) / 60)) minutes${err:+ ($err)}"
  fi
  awk -F'\t' -v r="$repo" '$1 != "" { print r "\t" $0 }' <<<"$cur"
}

# The wake for the new problems (<repo> TAB <key> TAB <kind> TAB <issues> TAB <text> lines): the first line names
# every issue by kind, per project, then one line per item.
wake() {
  jq -rRs 'split("\n") | map(select(. != "") | split("\t") | {repo: .[0], kind: .[2], issues: .[3], text: .[4]}) as $all
    | ($all | map(.repo) | unique) as $repos
    | ["needs the owner'"'"'s yes", "blocked", "stuck", "unreachable", "landed"] as $first
    | "Conveyor: " + ([$repos[] as $r | [$all[] | select(.repo == $r)] as $mine
        | ($first + ($mine | map(.kind) | unique - $first)) as $kinds
        | "\($r): " + ([$kinds[] as $k | [$mine[] | select(.kind == $k)] | select(length > 0)
            | (map(.issues | select(. != "")) | join(" ")) as $n | if $n == "" then $k else "\($k): \($n)" end] | join("; "))]
        | join(" | ")),
      ($all[] | "\(.repo): \(.text)")'
}

poll() { # 0 when a wake was put in pending
  local now=${CONVEYOR_FOREMAN_NOW:-$(date +%s)} cur= new await repo main df
  while IFS=$'\t' read -r repo main; do
    # [issue, its lines in await-<repo>.txt] for each awaited issue of the record past what was dropped: the count is
    # in its landed key, so an issue awaited again after its wake is a new key.
    await=$(awk 'FILENAME == ARGV[1] { done[$1] = $2; next } /^[1-9][0-9]*$/ { n[$0]++ }
      END { for (i in n) if (n[i] > done[i] + 0) print "[" i "," n[i] "]" }' "$FD/await-done-$repo.txt" "$FD/await-$repo.txt" | jq -sc sort)
    cur+=$(record "$repo" "$main" "$now" "$await")$'\n'
  done <<<"$RECS"
  new=$(awk -F'\t' '!cur { seen[$0]; next } $2 != "" && !(($1 "/" $2) in seen) && $5 != ""' "$SEEN" cur=1 - <<<"$cur")
  [ -z "$new" ] || wake <<<"$new" | pending_put || return 1
  awk -F'\t' '$2 != "" { print $1 "/" $2 }' <<<"$cur" > "$SEEN.tmp" && mv "$SEEN.tmp" "$SEEN" || return 1
  # An awaited issue is dropped only once its wake is in pending or was reported before; await-<repo>.txt is never
  # rewritten.
  while IFS=$'\t' read -r repo main; do
    df=$FD/await-done-$repo.txt
    awk -v p="$repo/landed:" 'FILENAME == ARGV[1] { if (index($0, p) == 1 && split(substr($0, length(p) + 1), k, ":") == 2) l[k[1]] = k[2]; next } { d[$1] = $2 }
      END { for (i in l) if (l[i] + 0 > d[i] + 0) d[i] = l[i]; for (i in d) print i, d[i] }' "$SEEN" "$df" > "$df.tmp" \
      && mv "$df.tmp" "$df" || return 1
  done <<<"$RECS"
  [ -n "$new" ]
}

while :; do
  poll && exit 0
  [ "${1:-}" != --once ] || exit 1
  sleep "$POLL"
done
