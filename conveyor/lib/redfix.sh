# SPDX-License-Identifier: Apache-2.0
# The fix card of a red main commit or a blocked push: its entry made for a push block (pushred()), its title (REDTITLE,
# redtitles()) and what stands in for its issue (redissue()). Sourced by lib/mainred.sh.
# A push that failed its check (kind check: pushone(), lib/push.sh) holds every landing back until main moves
# (checkheld()), as a red main does: main's commit holds a change the check refuses. Its fix card is made as a main-red one
# (issue 1683): an entry of <main's commit> in $MAINRED with no case and push: {check, card, issue (the landing the push was
# for), log, reason (the end of the push's output, for the brief: redissue())}, which the loop picks ahead of the queue, and
# beyond the cap (redpick(), run.sh redfix()). One fix card at a time for a check: while an entry of the same check has a
# fix card open (redopen(): on the belt or blocked), or one not picked yet (or given back) whose commit origin does not
# hold, a failure on a later commit adds nothing, as that card's change clears it. One whose commit origin holds (pushed
# by hand) is no block: redpick() drops it. Under the record's lock, as mainred().
pushred() { # <main's commit> <check> <card> <issue> [<the push's log>] [<its reason>]
  local lock rec s c open=false
  [ -n "$1" ] && [ -n "$2" ] || return 1
  { exec {lock}>>"$MAINRED.lock"; } 2>/dev/null && flock "$lock" \
    || { echo "conveyor: the main-is-red record could not be locked; the push block of $2 gets no fix card" >&2; return 1; }
  rec=$(jq -ce '.reds | arrays' "$MAINRED" 2>/dev/null) || rec='[]'
  while IFS=$'\t' read -r s c; do # The card goes last: read drops an empty tab-separated field between two others.
    redopen "$c" < /dev/null || continue
    if [ -z "$c" ] || [ -z "$(stdb ask card "$c" 2>/dev/null)" ]; then ! atorigin "$s" || continue; fi
    exec {lock}>&-; return 0
  done < <(jq -r --arg k "$2" '.[] | select(.push.check? == $k) | [.sha, .card // ""] | @tsv' <<<"$rec")
  # An entry of main's commit already (main red there too): it takes the push block, and its fix card, when open,
  # clears both; one whose card ended (closed as already done) is picked again.
  c=$(jq -r --arg s "$1" '.[] | select(.sha == $s) | .card // ""' <<<"$rec") && [ -n "$c" ] && redopen "$c" < /dev/null && open=true
  jq -c --arg s "$1" --arg k "$2" --arg c "$3" --arg n "$4" --arg l "${5:-}" --arg r "${6:-}" --argjson o "$open" '{push: ({check: $k, card: $c, issue: ($n | tonumber? // 0)}
      + (if $l == "" then {} else {log: $l} end) + (if $r == "" then {} else {reason: $r[-1500:]} end))} as $p
    | {reds: (if any(.[]; .sha == $s) then map(if .sha == $s then . + $p + (if $o then {} else {card: null} end) else . end)
        else . + [{sha: $s, cases: [], card: null} + $p] end | .[-100:])}' <<<"$rec" > "$MAINRED.new" \
    && mv -f "$MAINRED.new" "$MAINRED" || { exec {lock}>&-; echo "conveyor: the push block of $2: the main-is-red record could not be written" >&2; return 1; }
  exec {lock}>&-
}
# An entry's title (mainred()): "Main is red: <cases>"; a push block's (pushred()): "Push blocked: <check> fails on main", its cases after it.
REDTITLE='def redtitle: ((if .push then "Push blocked: \(.push.check) fails on main" + ([.cases[].case] | if . == [] then "" else "; main is red: " + join(", ") end)
  else "Main is red: " + ([.cases[].case] | join(", ")) end)[0:200]);'
# What stands in for the issue of a main-red fix card (card()), from its entry as it is now (mainred()): the title
# "Main is red: <cases>", and a body naming main's commit, each case with the last commit that changed its files (and
# the landing that broke it, when known), and what to do. Labelled as the P0 issue it stands in for was (labels.type and the first priority), so it is held to the bug-card check.
# A push block's entry (pushred()) is titled by REDTITLE; its body names the check, the landing, the push's log and error.
redissue() { # <card>
  jq -ce --arg c "$1" --arg t "$TYPE" --argjson p "$PRIOS" "$REDTITLE"'.reds[]? | select(.card == $c)
    | {number: 0, title: redtitle, milestone: null, labels: [{name: $t}, {name: $p[0]}],
       body: ((if .push == null then "" else "The push of main at \(.sha[0:12]) failed its check \(.push.check): the pre-push hook refused it, and it fails the same way on each try at that commit, so no landed card is pushed until a fix lands on main. The push was for card \(.push.card)\(if .push.issue > 0 then " (#\(.push.issue))" else "" end)."
           + (if .push.log then " The push'"'"'s whole output is in \(.push.log)." else "" end)
           + (if .push.reason then "\n\nThe end of its output:\n\n```\n\(.push.reason)\n```" else "" end)
           + "\n\nMake the check \(.push.check) pass on main.\(if .cases == [] then "" else "\n\n" end)" end)
         + (if .cases == [] then "" else "These test cases fail on main at \(.sha[0:12]). A card'"'"'s test step failed each on its run and its run again, and it failed again when run on main, without the card'"'"'s change. A card that fails only cases that fail on main waits (no fix session, no block) until main changes, then tests again.\n\n"
         + ([.cases[] | "- `\(.case)`, found by card \(.by). The last commit that changed \(if .files == [] then "its file" else .files | join(", ") end): \(if .last == "" then "none found" else .last end)."
           + if .landing == null then "" else " The landing that broke it: \(.landing.sha[0:12]) (card \(.landing.card), #\(.landing.issue)), whose test step did not run \(.files[0]). This card links \(.files[0]) to the files that landing changed, in .conveyor/test-links.json, so later cards that change them run it: \(.links | keys | join(", "))." end] | join("\n"))
         + "\n\nMake the cases pass on main." end)
         + "\n\nDone when: \([if .push then "the check \(.push.check) passes on main" else empty end, if .cases != [] then "the cases pass on main" else empty end] | join(", and ")).")}' "$MAINRED" 2>/dev/null
}
# The titles of the main-red fix cards as their entries are now ({<card>: "Main is red: <cases>"}): the Board shows a
# case added while the card runs (mainred()), which its picked line's title does not name.
redtitles() {
  jq -ce "$REDTITLE"'[.reds[]? | select(.card) | {key: .card, value: redtitle}] | from_entries' "$MAINRED" 2>/dev/null || echo '{}'
}
