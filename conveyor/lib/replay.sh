# SPDX-License-Identifier: Apache-2.0
# The judge replay study, run only when the owner asks (`conveyor.sh pick replay judge <model> [<effort>] [--last <n>]
# [--estimate]`, or the Board's Cost panel): another judge is given the findings the project's judge already ruled on,
# with their diffs, and its rulings are compared with the recorded ones. No card is touched, no setting is changed and
# no test runs: the only things written are the replay's own line in REPLAYS (lib/paths.sh) and the lock file beside
# it (REPLAYS.lock, which a run or an estimate makes when there is none, to let only one of them run at a time),
# besides the state database (state.db, state.py), which every read of the records through stdb() brings up to date.
# The cases are the newest <n> review lines (REPLAY_LAST when --last is not given) of the card records and the
# retried lines whose judge ruled (judge.accepted and judge.declined, judged(), lib/review.sh; a judge that failed
# ruled on nothing). A finding of a kind the project always accepts counts as the judge's own answer, which its reason
# keeps. The diff of a case is the card's change as the records keep it (the commit of its landed line, else the
# kept patch of its blocked line) on the commit its review sat on (main). That is the change as it ended: it is the
# one the judge read only when its patch-id (cardpatch(), lib/claim.sh) is the one the review line keeps (patch). A
# case with neither, or whose change is not the one its review read (a fix round came after it), is skipped. Each
# case's change is staged in a worktree of its own under a temporary folder, with the project's git hooks off, and
# removed after.
# The replay judge is the judge seat the control record would give for <model> and <effort> (seat(), as `control
# judge` would set it; the record is not written), called as the review calls the judge (judgecall()), with the issue's
# title and body as the brief, the findings the fix round before the review was told to fix and the findings already
# declined on the issue's cards before that judge ran, as judged() gives them.
REPLAY_LAST=20

# The cases, one JSON line each, oldest first: {card, issue, time, main, judge: the recorded judge's {model, effort,
# sec, tokens, usage}, findings: [{n, finding, place, accept}] in the order the judge was given them, sha: the landed
# commit or "", kept: the kept patch's path or "", patch: the patch-id of the change its review read or "", before:
# the lines of the findings already declined on the card or its issue before its judge ran ("- <finding> (declined:
# <why>) [kind: <kind, or none>]", the last 50, as judged() gives them), back: the findings of the fix round before
# this review, "- E<n> <finding> (accepted: <reason>)", or "- E<n> <finding>" for one the judge gave no readable line
# for (its cost null), as its judge was given them (fixedbefore(), lib/review.sh) and its line keeps them
# (judge.back); none when no fix round of the card ran (a card built from nothing after `retry <issue> --fresh`,
# say)}. A decline is before the judge ran when it is older than the review's
# line less the judge's seconds: the judge's own declines are written after its call ends. A line declined again under
# another kind (declined(), lib/followups.sh) gives the last of its rulings made before then: its earlier ones (was) and
# its latest (made at ruled, else at time).
replaycases() { # <n>
  { stdb ask lines retried -- lines cards; } 2>/dev/null | jq -cs --argjson last "$1" --arg st "$ST" --arg repo "$REPO" \
    --slurpfile dl <(stdb ask lines declined 2>/dev/null | jq -c 'objects' 2>/dev/null) '
    def t: try (sub("\\.[0-9]+"; "") | fromdateiso8601) catch null;
    map(objects) as $all
    | [$all[] | select(.step == "review" and (.judge | type) == "object" and .judge.failed == null
        and ([.judge.accepted, .judge.declined | arrays[]] | length) > 0)]
    | sort_by(.time) | .[-$last:][] | .card as $c | .issue as $n |(.judge.sec | numbers // 0) as $sec | (.time | t | if . == null then null else . - $sec end) as $ran
    | {card: $c, issue, time, main: (.main // ""), patch: (.patch // ""),
       back: [.judge.back | arrays[] | strings],
       before: ([$dl[] | select((.card == $c or (.issue == $n and $n != 0 and .repo == $repo)) and $ran != null)
                 | .finding as $f | [(.was // [])[], {time: (.ruled // .time), why, kind}] | map(select(((.time | t) // $ran) < $ran)) | last // empty
                 | "- \($f) (declined: \(.why)) [kind: \(.kind // "none")]"] | reduce .[] as $l ([]; if index([$l]) then . else . + [$l] end) | .[-50:]), judge: (.judge | {model, effort, sec, tokens, usage} | del(.[] | nulls)),
       findings: ([(.judge.accepted | arrays[] | . + {accept: (.reason | tostring | test("^always accepted: a .* finding \\(the judge declined it: ") | not)}),
                   (.judge.declined | arrays[] | . + {accept: false})] | sort_by(.n) | map({n, finding, place, accept})),
       sha: ([$all[] | select(.card == $c and .step == "landed" and (.sha // "") != "") | .sha] | last // ""),
       kept: ([$all[] | select(.card == $c and .step == "blocked" and (.kept // "") != "") | "\($st)/\(.kept)/\($c).patch"] | last // "")}'
}
# The case's change as a patch: the landed commit's own diff, else the kept patch.
replaypatch() { # <sha> <kept>
  if [ -n "$1" ]; then git -C "$MAIN" diff --binary --no-renames "$1^" "$1"; else cat "$2"; fi
}
# Whether a case's change can be staged and is the change its review read: the commit its review sat on (main) is in
# the repository with the landed commit and its parent, or with the kept patch; the change applies on that commit (a
# landed commit's parent can be a later main, with other cards' lines in the same files); and its patch-id there, made
# as cardpatch() makes it, is the review line's patch.
replayable() { # <case json>
  local sha kept base patch i p
  jqget "$1" sha sha kept kept main base patch patch && [ -n "$patch" ] && [ -n "$base" ] \
    && git -C "$MAIN" rev-parse -q --verify "$base^{commit}" >/dev/null || return 1
  if [ -n "$sha" ]; then git -C "$MAIN" rev-parse -q --verify "$sha^^{commit}" >/dev/null || return 1
  else [ -n "$kept" ] && [ -s "$kept" ] || return 1; fi
  i=$(mktemp -d) || return 1
  p=$(export GIT_INDEX_FILE=$i/index; git -C "$MAIN" read-tree "$base" 2>/dev/null && replaypatch "$sha" "$kept" | git -C "$MAIN" apply --cached 2>/dev/null \
    && git -C "$MAIN" diff --cached --binary --no-renames -U0 "$base" 2>/dev/null | diffid 2>/dev/null)
  rm -rf "$i"
  [ -n "$p" ] && [ "$p" = "$patch" ]
}
# The case's change, staged in a new worktree <folder>/wt on the commit its review sat on, as its review read it.
replaywt() { # <case json> <folder>
  local sha kept base
  replayable "$1" && jqget "$1" sha sha kept kept main base || return 1
  git -C "$MAIN" -c core.hooksPath=/dev/null worktree add -q --detach "$2/wt" "$base" >/dev/null 2>&1 \
    && replaypatch "$sha" "$kept" | git -C "$2/wt" apply --index 2>/dev/null
}
# The dollars of judge calls at list price (dashboard_limit.py work, the Board's price table with the pack's prices
# over it): steps [{model, usage, tokens}]; null when one of them has no price.
replayusd() { # < <steps json array>
  local pp; packget prices pp 2>/dev/null && [ -n "$pp" ] || pp='{}'
  jq -c --argjson p "$pp" '{steps: map({step: "judge", model, usage, tokens}), live: null, prices: $p}' \
    | python3 "$HERE/../.claude/scripts/dashboard_limit.py" work 2>/dev/null | jq -c 'if .state == "known" then .usd else null end' 2>/dev/null || echo null
}
# The replay. With --estimate it calls no model: it prints {estimate: true, model, effort, reviews, skipped, findings,
# usd: the recorded judges' token use priced at <model>, recordedUsd}. Else it calls the judge once a case and appends
# one line to REPLAYS, which it also prints: {time, seat: "judge", model, effort, last, reviews (the cases replayed),
# skipped (the cases with no change to stage, or not the change their review read), findings (those compared),
# agree, unanswered (the findings of a call that failed or gave no line for them), differ: [{card, issue, n, finding, recorded, replay: "accept" or "decline",
# reason: the replay judge's}], usd (the replay's calls), recordedUsd (the recorded judges of the same cases), calls:
# each call's own usage, {card, issue, model, effort, sec, tokens, usage}, with failed (why) when it failed}. One
# replay runs at a time.
replay() { # judge <model> [<effort>] [--last <n>] [--estimate]
  local model effort='' last=$REPLAY_LAST est='' x rc c s cs=() k d w f out ans skipped=0 brief before back iss fd
  local use='usage: conveyor.sh pick replay judge <model> [<effort>] [--last <n>] [--estimate]'
  [ "${1:-}" = judge ] && [ -n "${2:-}" ] && [[ $2 != --* ]] || { echo "$use" >&2; return 2; }
  model=$2; shift 2
  [ $# = 0 ] || [[ $1 == --* ]] || { effort=$1; shift; }
  while [ $# -gt 0 ]; do
    case $1 in --last) [[ ${2:-} =~ ^[1-9][0-9]{0,3}$ ]] || { echo "$use" >&2; return 2; }; last=$2; shift 2 ;; --estimate) est=1; shift ;; *) echo "$use" >&2; return 2 ;; esac
  done
  x=$(cardok judge "$model" "$effort") || return 1
  [ -z "$x" ] || { echo "conveyor: $x; no replay ran" >&2; return 2; }
  c=$(ctl) || return 1
  s=$(SEATCARD='' seat judge "$(jq -c --arg m "$model" --arg e "$effort" '.judge = ({model: $m} + if $e == "" then {} else {effort: $e} end)' <<<"$c")") && [ -n "$s" ] \
    && jqget "$s" effort effort || { echo "conveyor: the pack gives the judge no seat on $model; no replay ran" >&2; return 1; }
  # An estimate while a replay runs is refused too: the Board starts a run only after an estimate of it succeeds.
  exec {fd}>>"$REPLAYS.lock" && flock -n "$fd" || { echo "conveyor: a replay is running already; no replay ran" >&2; return 1; }
  mapfile -t cs < <(replaycases "$last")
  [ "${#cs[@]}" -gt 0 ] || { echo "conveyor: no review line holds rulings of the judge to replay; no replay ran" >&2; return 1; }
  # What the cases add up to is kept in files of <w>, one JSON line each, never in a command's arguments: a hundred
  # cases' records are over the system's limit of one argument.
  w=$(mktemp -d) && touch "$w/rec" "$w/calls" "$w/steps" "$w/rows" || { echo "conveyor: no temporary folder for the replay; no replay ran" >&2; return 1; }
  if [ -n "$est" ]; then
    for k in "${cs[@]}"; do if replayable "$k"; then printf '%s\n' "$k" >> "$w/rec"; else skipped=$((skipped + 1)); fi; done
    jq -cs --arg m "$model" --arg e "$effort" --argjson s "$skipped" --argjson u "$(jq -cs --arg m "$model" 'map(.judge | .model = $m)' "$w/rec" | replayusd)" \
      --argjson ru "$(jq -cs 'map(.judge)' "$w/rec" | replayusd)" \
      '{estimate: true, model: $m, effort: $e, reviews: length, skipped: $s, findings: ([.[].findings[]] | length), usd: $u, recordedUsd: $ru}' "$w/rec"
    rm -rf "$w"; return 0
  fi
  # The accounts a review of a card started now would use (cardaccts(), as Pick for me reads them).
  mapfile -t x < <(SEATCARD='' cardaccts "$c")
  # shellcheck disable=SC2034 # ACCT and RACCT are read by judgecall() in lib/review.sh
  local ACCT=${x[0]-} RACCT=${x[1]-}
  # The judge's prompt as a review's judge is given it now (judgeprompt(), with the control record's rare-case levels).
  local jp; jp=$(judgeprompt)
  for k in "${cs[@]}"; do
    d=$(mktemp -d) || break # the calls made so far are still written, with their usage
    if ! replaywt "$k" "$d"; then skipped=$((skipped + 1)); git -C "$MAIN" worktree remove --force "$d/wt" >/dev/null 2>&1; rm -rf "$d"; continue; fi
    iss=$(gh issue view "$(jq -r .issue <<<"$k")" --json number,title,body 2>/dev/null) && jq -e 'objects | .number' <<<"$iss" >/dev/null 2>&1 \
      && brief=$(jq -r '"# The issue\n#\(.number) \(.title // "")\n\n\(.body // "")"' <<<"$iss") || brief="# The issue"$'\n'"#$(jq -r .issue <<<"$k") (its text could not be read)"
    printf '%s\n' "$k" > "$d/case"
    # The findings declined on the issue's cards before the recorded judge ran, given as judged() gives them.
    before=$(jq -r '.before | arrays | if length > 0 then "# Findings already declined on the cards of this issue\n\(join("\n"))" else empty end' <<<"$k")
    # The findings the fix round before the review was told to fix, with the judge's earlier reason for each it gave a readable line for, as judged() gives them.
    back=$(jq -r '.back | arrays | if length > 0 then "# The findings the last fix round was told to fix\n\(join("\n"))" else empty end' <<<"$k")
    out=$(CALLSEAT=$s CALLSTEP=replay CALLACT="the replay judge reads the findings of $(jq -r .card <<<"$k")" judgecall "$d/wt" "$jp" "$brief"$'\n\n'"${back:+$back$'\n\n'}${before:+$before$'\n\n'}# The findings"$'\n'"$(jq -r '.findings
      | to_entries[] | "F\(.key + 1) [\({inside: "inside the diff", outside: "outside the diff"}[.value.place] // "no place")] \(.value.finding)"' <<<"$k")") && f=ok || f=''
    jq -e objects <<<"$out" >/dev/null 2>&1 || out='{"failed": "the judge call printed no fields"}'
    ans='[]'; [ -z "$f" ] || ans=$(jq -cRn '[inputs | gsub("^[[:space:]`*-]+|[[:space:]`*]+$"; "") | capture("^F(?<n>[0-9]+) (?<d>ACCEPT|DECLINE):[[:space:]]*(?<r>.*)$")]' "$d/wt.judge" 2>/dev/null) || ans='[]'
    jq -c --slurpfile k "$d/case" '$k[0] as $k | {card: $k.card, issue: $k.issue} + ({model, effort, sec, tokens, usage, failed} | del(.[] | nulls))' <<<"$out" >> "$w/calls"
    printf '%s\n' "$out" >> "$w/steps"; jq -c .judge <<<"$k" >> "$w/rec"
    # Each finding's ruling: the one line the replay judge gave for it, else none (unanswered).
    jq -c --slurpfile k "$d/case" '$k[0] as $k | . as $a | $k.findings | to_entries[] | (.key + 1) as $i | .value as $x
      | [$a[] | select((.n | tonumber) == $i)] as $d
      | {card: $k.card, issue: $k.issue, n: $x.n, finding: $x.finding, recorded: (if $x.accept then "accept" else "decline" end),
         replay: (if ($d | length) == 1 then $d[0].d | ascii_downcase else null end), reason: (if ($d | length) == 1 then $d[0].r else null end)}' <<<"$ans" >> "$w/rows"
    git -C "$MAIN" worktree remove --force "$d/wt" >/dev/null 2>&1; rm -rf "$d"
  done
  out=$(jq -cs --arg m "$model" --arg e "$effort" --argjson last "$last" --argjson s "$skipped" --slurpfile c "$w/calls" \
    --argjson u "$(jq -cs . "$w/steps" | replayusd)" --argjson ru "$(jq -cs . "$w/rec" | replayusd)" \
    '{time: (now | todate), seat: "judge", model: $m, effort: $e, last: $last, reviews: ($c | length), skipped: $s, findings: (map(select(.replay != null)) | length),
      agree: (map(select(.replay != null and .replay == .recorded)) | length), unanswered: (map(select(.replay == null)) | length),
      differ: map(select(.replay != null and .replay != .recorded)), usd: $u, recordedUsd: $ru, calls: $c}' "$w/rows"); rc=$?
  rm -rf "$w"; [ $rc = 0 ] || return 1
  printf '%s\n' "$out" >> "$REPLAYS" || { echo "conveyor: the replay could not be written to $REPLAYS" >&2; printf '%s\n' "$out"; return 1; }
  printf '%s\n' "$out"
}
