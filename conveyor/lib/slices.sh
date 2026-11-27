# SPDX-License-Identifier: Apache-2.0
# The rule Split large issues (the control record's rules.split: off, shadow or on; on by default). card() asks
# splitcheck() once, as the card starts, once its worktree is made and holds no stray staged change (cardtree(), lib/card.sh), and before the build, for an issue of its own (not a main-red fix
# card, issue 0, nor a branch). Its issue is left out when it is a follow-up (the pack's follow-up label: the slices of
# a split issue have it too), or when a split line of the card records or the retried lines already holds the same
# text of it (hash: the git hash of its title, a newline and its body): an issue is checked again only once it has
# been edited, or when it has SPLIT_TRIES blocked cards or more, once for each text of the issue (a forced check, below).
# Code first: the issue's size (SPLITSIZE: the items of its Done when section, the file paths and area labels it names,
# its characters) against the pack's split thresholds (split.doneWhen, split.files, split.areas, split.chars). An issue
# under all of them is kept with no model call, unless a forced check (below) is made. One at or over one of them is given to the judge (the Rules tab's
# Judge, the seat judgeseat() names), with no tools, once and SPLIT_TIMEOUT at most: its title and body, its Done-when
# items numbered D1, D2 and so on, and the files it names as they are on main (the first SPLIT_FILE characters of each,
# SPLIT_FILES files at most). The judge answers keep, or split into 2 or 3 slices (SPLITASK). An answer is used only
# when it holds to the rules (SPLITREAD): each slice has a title, Done-when items of its own and the parent's items it
# covers; every item of the parent is covered by exactly one slice; a slice depends only on slices before it. Any other
# answer, or a call that fails, keeps the issue whole, and the line says why.
# A forced check (splitforce()): an issue with SPLIT_TRIES blocked cards or more, given back by `retry`, is given to the
# judge whatever its hash line and its size say, with the block reason of its last two blocked cards in the prompt, and
# its line holds forced: true. It is made once for each text of the issue, and not when the kept patch of the last
# blocked card waits only for the owner's yes (yeskept(), lib/issues.sh) or was given back by review-land. Any answer
# but a valid split builds the issue whole, as the rest of this rule does.
# The card's split line records it: result kept or split, and split {mode (the rule: shadow or on), hash, verdict
# (under: under the thresholds; keep; split; invalid: an answer that broke the rules; failed: the call failed), why,
# size, slices ({title, doneWhen, covers, dependsOn}, each slice's number from 1), filed (the issues filed, On only),
# held (On only: whether they started held, as the issue was, or queued), resumed (the card whose plan this card
# finished or ended: splitplan()), answer (the start of an answer that broke the rules)}, and model (the judge's) when
# the judge was asked. Before the first slice is filed, the start line of the filing holds the plan: {split, cards
# (whether the slices are cards with no GitHub issue)}. A card that stops after that and before its split line leaves
# the plan unrecorded: while the rule is On and the issue's text is the plan's, the next card of the issue files the
# slices it lacks (splitmade()), keeps those it filed, picked or not, where they are, and records the split as its own
# line with resumed, with no new judge call. Else (the rule is Shadow, or the issue was edited) it ends the plan: it
# gives the issue back the slices' place in the pick order, withdraws the slices filed for it, and checks the issue as
# any other. With the rule Off the plan is ended the same way, with no line, and the issue is built whole. A card whose
# plan's slices cannot be read, or not all withdrawn (a close GitHub did not confirm, a slice that a card took: a close
# does not stop that card), is blocked: built whole, it could build their work twice.
# In shadow the card goes on and builds the issue whole, as with the rule off. On, with a split verdict, the slices are
# filed as follow-ups of the issue (splitfile()), held or queued as the issue is, and in its place in the pick order
# when the order names it; the issue becomes their umbrella: it is held (`control hold`), the
# slices are attached as its GitHub sub-issues (attachparts()), it gets a comment naming the slice that covers each of
# its Done-when items, and the card ends with a closed line whose followups are the slices (so a run limited by --only
# to the issue takes its slices too, ups() in DEPS); the issue stays open. umbrellas() closes it once each of its sub-issues
# is closed or landed, push on or off (or, when they could not be attached, once each slice has a card that landed or closed it as done). A slice that cannot be filed withdraws the
# ones filed before it, and the issue is built whole. So is an issue with a slice open that an earlier card of it filed
# for its grown change (growopen()), or whose open follow-ups cannot be read: nothing is filed, as a slice of this
# split could build that slice's work a second time.
SPLIT_TIMEOUT=300 SPLIT_FILE=6000 SPLIT_FILES=10
# The blocked cards of an issue (given back by `retry`) at which splitcheck() asks the judge again, whatever the hash
# check and the limits say (splitforce()). Its one reader is splitcheck().
SPLIT_TRIES=2
# The issue (its input, as gh issue view gives it) as the split check measures it. $area is the pack's area prefix.
# The Done when section is a heading or a line "Done when", "Acceptance criteria" or "Definition of done" (in bold or
# with a colon too; the first one in the issue) up to the next heading; its
# items are its bullets at the least indent (a nested bullet is part of its item). A file path is a word with a dot
# and an extension that starts with a letter, two characters or more before that dot (not e.g. or 4.7M); it can start
# with a dot, as a path in a hidden directory does (.claude/x.js).
SPLITSIZE='def dwsect: [splits("\r?\n")] as $l
    | ([range($l | length) | select($l[.] | test("^\\s*(#{1,6}\\s*)?(\\*\\*)?(Done when|Acceptance criteria|Definition of done)(\\*\\*)?\\s*:?\\s*(\\*\\*)?\\s*:?\\s*$"; "i"))] | first) as $i
    | if $i == null then [] else $l[($i + 1):] | (map(test("^\\s*#{1,6}\\s")) | index(true)) as $e | if $e == null then . else .[:$e] end end;
  def items: map(select(test("^\\s*[-*+]\\s+\\S"))) | (map(capture("^(?<i>\\s*)").i | length) | min) as $m
    | map(select((capture("^(?<i>\\s*)").i | length) == $m) | sub("^\\s*[-*+]\\s+"; "") | sub("\\s+$"; ""));
  (.body // "") as $b
  | {doneWhen: ($b | dwsect | items),
     files: ([$b | scan("(?<![A-Za-z0-9_./-])\\.?[A-Za-z0-9_][A-Za-z0-9_./-]*[A-Za-z0-9_]\\.[A-Za-z][A-Za-z0-9]{0,7}(?![A-Za-z0-9_/-])")] | unique),
     areas: (if $area == "" then 0 else [((.labels // [])[] | .name), ($b | splits("[\\s`\"'"'"'(),;<>]+") | sub("[.:]+$"; ""))]
       | map(select(startswith($area) and length > ($area | length))) | unique | length end),
     chars: ((.title // "") + "\n" + $b | length)}'
SPLITASK='One coding session is about to build the issue below as one change. Large issues often go wrong when they are
built as one change. Decide whether this issue is better built as 2 or 3 smaller issues (slices), each built,
reviewed and landed on its own, one after the other.
The rules of a split:
- Each slice is a complete change that works on its own. Never half a feature, and never code that works only when a
  later slice lands.
- Each slice has a title, Done-when items of its own, and the numbers of the Done-when items of the issue that it
  covers (D1, D2 and so on, as they are numbered below).
- Each Done-when item of the issue is covered by exactly one slice.
- A slice that changes the same code as an earlier slice depends on it: give the numbers of the earlier slices it
  depends on (1 is the first slice).
- 2 or 3 slices, never more.
Keep the issue whole when its parts cannot each work on their own, or when a split does not make each part clearly
smaller. When you are not sure, keep it.
Answer with exactly one JSON object and nothing else, one of:
{"verdict": "keep", "why": "<one line>"}
{"verdict": "split", "why": "<one line>", "slices": [{"title": "<title>", "doneWhen": ["<item>"], "covers": [<item number of the issue>], "dependsOn": [<number of an earlier slice>]}]}'
# The judge's answer (its input, raw) against the rules of a split, for an issue of $n Done-when items: {verdict, why}
# with slices for a split; {verdict: "invalid", why, answer} for an answer that breaks them; nothing when no JSON
# object can be read from it. Its first `{` to its last `}` is the object (a fence or a line around it is dropped).
SPLITREAD='def nums: type == "array" and all(.[]; type == "number" and . == floor);
  def ds($x): $x | map("D\(.)") | join(", ");
  . as $raw | (index("{")) as $s | (rindex("}")) as $e | select($s != null and $e != null and $s < $e) | .[$s:$e + 1] | fromjson? | objects
  | (.why | if type == "string" then .[0:300] else "" end) as $why
  | (if .verdict == "keep" then null
     elif .verdict != "split" then "the verdict is neither keep nor split"
     elif (.slices | type) != "array" then "a split with no list of slices"
     elif (.slices | length) < 2 or (.slices | length) > 3 then "\(.slices | length) slices, not 2 or 3"
     elif any(.slices[]; (.title | type) != "string" or (.title | test("\\S") | not)) then "a slice has no title"
     elif any(.slices[]; .doneWhen | type != "array" or length == 0 or any(.[]; type != "string" or (test("\\S") | not))) then "a slice has no Done-when items of its own"
     elif any(.slices[]; (.covers | nums | not) or (.covers | length) == 0) then "a slice covers none of the Done-when items of the issue"
     elif any(.slices | to_entries[]; .key as $k | .value.dependsOn // [] | (nums | not) or any(.[]; . < 1 or . > $k)) then "a slice depends on a slice that is not before it"
     else [.slices[].covers[]] as $c | ([range(1; $n + 1)] - $c) as $miss | ($c - [range(1; $n + 1)]) as $out
       | ($c | group_by(.) | map(select(length > 1) | .[0])) as $twice
       | if $out != [] then "a slice covers \(ds($out | unique)), which the issue does not have"
         elif $miss != [] then "no slice covers \(ds($miss))"
         elif $twice != [] then "more than one slice covers \(ds($twice))" else null end end) as $bad
  | if $bad != null then {verdict: "invalid", why: $bad, answer: $raw[0:2000]}
    elif .verdict == "keep" then {verdict: "keep", why: $why}
    else {verdict: "split", why: $why, slices: [.slices[] | {title: (.title | gsub("\\s+"; " ") | .[0:200]), doneWhen: (.doneWhen | map(gsub("\\s+"; " "))),
      covers: (.covers | unique), dependsOn: (.dependsOn // [] | unique)}]} end'
# One call of the judge (the seat judgeseat() names; CONVEYOR_SPLIT_CMD in the cases), no tools, SPLIT_TIMEOUT at
# most: sets the caller's ans to its answer and model to the judge's model; fails with why in ans.
splitcall() { # <the control record> <prompt>
  local s effort='' d rc
  model=''; s=$(seat judge "$1" 2>/dev/null) && jqget "$s" model model effort effort || { model='' effort=''; }
  d=$(mktemp -d) || { ans="the judge call failed (no folder for it)"; return 1; }
  if [ -n "${CONVEYOR_SPLIT_CMD:-}" ]; then
    (cd "$d" && exec timeout --kill-after=10 "$SPLIT_TIMEOUT" bash -c "$CONVEYOR_SPLIT_CMD" <<<"$2" > "$d/answer" 2>/dev/null 8>&- 9>&-); rc=$?; s=''
  else s=$(ASKSEAT=judge askmodel "$d" "$SPLIT_TIMEOUT" "${effort:-medium}" "$1" "$2"); rc=$?; fi
  ans=$(cat "$d/answer" 2>/dev/null); rm -rf "$d"
  [ "$rc" = 0 ] && [ -z "$s" ] || { ans="the judge call failed (${s:-exit $rc; 124 is the ${SPLIT_TIMEOUT}s timeout})"; return 1; }
}
# The judge's prompt: SPLITASK, the issue, its Done-when items and the files it names, as main has them.
splitprompt() { # <issue json> <size json> [<the block reasons of a forced check, a json list>]
  local f n=0 t p
  p=$SPLITASK$'\n\n'$(jq -r --argjson s "$2" '"# The issue: #\(.number) \(.title // "")\n\n\(.body // "")\n\n# Its Done-when items\n"
    + ($s.doneWhen | to_entries | map("D\(.key + 1): \(.value)") | join("\n") | if . == "" then "(none)" else . end)' <<<"$1")
  p+=$'\n\n# The files it names, as they are on main'
  while IFS= read -r f && [ "$n" -lt "$SPLIT_FILES" ]; do
    t=$(git -C "$MAIN" show "refs/heads/$BRANCH:${f#./}" 2>/dev/null) || continue
    n=$((n + 1)); p+=$'\n\n## '"$f ($(wc -l <<<"$t" | tr -d ' ') lines)"$'\n'"${t:0:$SPLIT_FILE}"
  done < <(jq -r '.files[]' <<<"$2")
  [ "$n" != 0 ] || p+=$'\n\n(none of them is a file on main)'
  [ -z "${3:-}" ] || p+=$'\n\n# This issue was built twice and nothing landed\nAnswer with a split into 2 or 3 slices. Why each of its last blocked cards stopped:\n'$(jq -r 'map("- " + .) | join("\n")' <<<"$3")
  printf '%s' "$p"
}
# Whether splitcheck() is made to ask the judge for <issue> (text hash <hash>): the issue has SPLIT_TRIES blocked cards
# or more (distinct cards of its blocked lines that `retry` gave back), no forced check of this text is on record, and
# the kept patch of its last blocked card is not one that waits only for the owner's yes (yeskept()) or was given back
# by review-land. Prints the block reasons of the last two blocked cards (300 characters each, a json list) and
# succeeds; fails when no check is forced, also when the blocked cards cannot be read.
splitforce() { # <issue> <hash>
  local b prev
  b=$(stdb ask issue retried "$1" 2>/dev/null | jq -sc --argjson n "$1" 'map(select(.issue == $n and .step == "blocked")) | sort_by(.time) | group_by(.card) | map(last) | sort_by(.time)' 2>/dev/null) || return 1
  [ "$(jq 'length' <<<"$b" 2>/dev/null)" -ge "$SPLIT_TRIES" ] 2>/dev/null || return 1
  prev=$(prior "$1") && [ -n "$prev" ] && { yeskept "$prev" || [ "$(jq -r '.by' <<<"$prev")" = review-land ]; } && return 1
  [ "$({ recs; olds; } 2>/dev/null | grep -F "\"$2\"" | jq -Rn --argjson n "$1" --arg h "$2" \
    'any(inputs | fromjson? | objects; .step == "split" and .issue == $n and .split.hash == $h and .split.forced == true)' 2>/dev/null)" != true ] || return 1
  jq -c '.[-2:] | map((.reason // "")[0:300])' <<<"$b"
}
splitcheck() { # <card> <issue>: 0 when the card goes on to build; 1 when the card has ended (the issue was split, or the card blocked)
  local c=${CARDCTL:-} rule issue h size t1 t2 t3 t4 p ans v model='' nums x w split sf me by res made old gone force=''
  [ -n "$c" ] || c=$(ctl 2>/dev/null) || return 0
  rule=$(jq -r '.rules.split // "off"' <<<"$c" 2>/dev/null)
  # A grown filing that a card of the issue stopped in (growresume()), under each rule; one not finished blocks the card.
  x=$(growresume "$1" "$2") || { block "$1" "$2" "$CARDS/$1" "grown: an earlier card stopped as it filed slices of #$2 in place of others, and $x"; return 1; }; [ -z "$x" ] || record "$1" "$2" start ok "$x"
  # A split a card of the issue planned and did not record (splitplan()), under each rule. Bug: it was filed twice.
  by=$1 res='' gone='' made='[]' sf=splitfile
  x=$(splitplan "$2") || return 0
  if [ -n "$x" ]; then
    old=${x%%$'\t'*} x=${x#*$'\t'}
    [ "$(jq -r .cards <<<"$x")" != true ] || sf=splitcards
    # Slices not read, or not all withdrawn (splitend()), may stay queued: the card is blocked. Bug: built whole beside them.
    made=$(splitmade "$old" "$2" "$sf") || { splitstop "$1" "$2" "card $old planned a split of #$2 and stopped before it was recorded, and $made"; return 1; }
    # Off builds the issue whole, the plan ended with no line. Bug: Off did not read the plan, and left its slices queued.
    if [ "$rule" != shadow ] && [ "$rule" != on ]; then
      gone=$(splitend "$old" "$2" "$sf" "$made") || { splitstop "$1" "$2" "${gone#; }"; return 1; }
      echo "conveyor: card $1: the rule Split large issues is Off$gone" >&2; return 0
    fi
  fi
  [ "$rule" = shadow ] || [ "$rule" = on ] || return 0
  # An issue that cannot be read is built as it is, with no line: its card reads it again (card()).
  issue=$(gh issue view "$2" --json number,title,body,labels,milestone 2>/dev/null) && jq -e 'objects | .number' <<<"$issue" >/dev/null 2>&1 || return 0
  ! jq -e --arg fu "$FOLLOWUP" 'any(.labels[]?; .name == $fu)' <<<"$issue" >/dev/null 2>&1 || return 0
  size=$(jq -c --arg area "$AREA" "$SPLITSIZE" <<<"$issue") || return 0
  h=$(jq -j '.title // "", "\n", .body // ""' <<<"$issue" | git hash-object --stdin) && [ -n "$h" ] || return 0
  if [ -n "$x" ]; then
    if [ "$rule" = on ] && [ "$(jq -r .split.hash <<<"$x")" = "$h" ]; then
      # Rule On and the plan's text: this card files the slices the plan lacks, with no new judge call.
      by=$old res=1 split=$(jq -c --arg b "$old" '.split + {resumed: $b}' <<<"$x") || return 0
    else
      # Shadow, or an edited issue (the plan's slices cover its old items): the plan is ended (splitend()), and the issue
      # checked anew. Bug: the next card filed the plan's missing slices under Shadow, or with an edited issue's new items.
      gone=$(splitend "$old" "$2" "$sf" "$made") || { splitstop "$1" "$2" "${gone#; }"; return 1; }
      made='[]' sf=splitfile
    fi
  fi
  [ -n "$res$gone" ] || force=$(splitforce "$2" "$h") || force='' # a forced check passes over the hash check and the limits
  [ -n "$res$gone$force" ] || [ "$({ recs; olds; } 2>/dev/null | grep -F "\"$h\"" | jq -Rn --argjson n "$2" --arg h "$h" \
    'any(inputs | fromjson? | objects; .step == "split" and .issue == $n and .split.hash == $h)' 2>/dev/null)" != true ] || return 0
  [ -n "$res" ] || packget split.doneWhen t1 split.files t2 split.areas t3 split.chars t4 || return 0
  if [ -n "$res" ]; then : # the plan's split
  elif [ -z "$force" ] && jq -e --argjson t "[$t1,$t2,$t3,$t4]" '(.doneWhen | length) < $t[0] and (.files | length) < $t[1] and .areas < $t[2] and .chars < $t[3]' <<<"$size" >/dev/null; then
    v=$(jq -c '{verdict: "under", why: "under the pack'"'"'s split thresholds: \(.doneWhen | length) Done-when items, \(.files | length) files, \(.areas) areas, \(.chars) characters"}' <<<"$size")
  else
    p=$(splitprompt "$issue" "$size" "$force")
    # The judge call can take SPLIT_TIMEOUT, before the card's worktree line names its process: its start line names
    # it (pid, started, as the worktree line does), so `shut` and `retry` find the card (stuckcard(), lib/run.sh).
    # Bug: a card that waited here, or died here, could not be ended outside a running loop.
    me=$BASHPID
    record "$1" "$2" start ok "$(jq -cn --argjson p "$me" --arg t "$(p_started "$me")" '{of: "split"} + (if $t == "" then {} else {pid: $p, started: $t} end)')"
    if ! splitcall "$c" "$p"; then v=$(jq -cn --arg r "$ans" '{verdict: "failed", why: $r}')
    else v=$(jq -Rsc --argjson n "$(jq '.doneWhen | length' <<<"$size")" "$SPLITREAD" <<<"$ans" 2>/dev/null)
      [ -n "$v" ] || v=$(jq -cn --arg a "${ans:0:2000}" '{verdict: "invalid", why: "the answer held no JSON object", answer: $a}'); fi
  fi
  [ -n "$res" ] || split=$(jq -c --arg m "$rule" --arg h "$h" --argjson s "$size" '{mode: $m, hash: $h, size: ($s | .doneWhen |= length | .files |= length)} + (if $f then {forced: true} else {} end) + .' --argjson f "$([ -n "$force" ] && echo true || echo false)" <<<"$v") || return 0
  [ -z "$gone" ] || split=$(jq -c --arg b "$old" --arg w "$gone" '. + {resumed: $b} | .why += $w' <<<"$split") || return 0
  [ -n "$res" ] || [ "$(jq -r '.rules.splitissues' <<<"$c" 2>/dev/null)" != false ] || sf=splitcards # Cards with no GitHub issue: Split parts On
  # On, a split is filed; one that cannot be filed is recorded as a split not filed, and the issue is built whole (the
  # card is blocked when a slice it filed may stay open). Not while a slice that an earlier card filed for its grown
  # change is open (growopen()): a slice of this split could build its work twice. A plan this card was to finish is
  # then ended (splitend()). Bugs: a second copy of an open grown slice; the plan's slices queued beside the issue.
  if [ "$rule" = on ] && [ "$(jq -r .verdict <<<"$split")" = split ]; then
    if ! x=$(growopen "$2"); then x="the open follow-ups of #$2 could not be read"
    elif [ "$x" != '[]' ]; then x="$(jq -r 'map("#\(.n)") | join(", ")' <<<"$x"), slices that earlier cards filed for its grown changes, are still open"
    else x=''; fi
    if [ -n "$x" ]; then
      w=''; [ -z "$res" ] || w=$(splitend "$old" "$2" "$sf" "$made") || { splitstop "$1" "$2" "${w#; }"; return 1; }
      split=$(jq -c --arg r "$x" --arg w "$w" '.why += "; \($r), so no slice is filed and the issue is built whole\($w)"' <<<"$split")
    else
      # stop (halt(), lib/run.sh) leaves the card to finish from here: its slices are being filed. Its start line holds
      # the plan (the split and whether its slices are cards) before the first slice is filed, for splitplan(), on disk
      # (RECSYNC, append(), lib/records.sh: a line that is not ends the card). Bug: a power cut after a slice was
      # filed could lose the plan, and the next card filed that slice again.
      x=''; [ -n "$res" ] || x=$(jq -c --arg sf "$sf" '{plan: {split: ., cards: ($sf == "splitcards")}}' <<<"$split")
      RECSYNC=1 began "$1" "$2" file "$x" || { made='' nums='the plan of the split could not be recorded'; }
      if [ -z "$made" ]; then :
      elif nums=$($sf "$by" "$issue" "$(jq -c .slices <<<"$split")" 1 "$made"); then split=$(jq -c --argjson f "$nums" '. + $f' <<<"$split") nums=''
      elif [ $? = 2 ]; then splitstop "$1" "$2" "the slices of the split could not be filed whole: $nums"; return 1; fi # some may stay in the queue
      [ -z "$nums" ] || split=$(jq -c --arg r "$nums" '.why += "; the slices could not be filed, so the issue is built whole: \($r)"' <<<"$split")
    fi
  fi
  record "$1" "$2" split "$(jq -r 'if .verdict == "split" then "split" else "kept" end' <<<"$split")" \
    "$(jq -c --arg m "$model" '{split: .} + (if $m != "" and .verdict != "under" then {model: $m} else {} end)' <<<"$split")"
  jq -e '.filed' <<<"$split" >/dev/null || return 0
  # The umbrella: held, told which slice covers each Done-when item, and its card closed; the issue stays open.
  x=$(locked control hold "$2" 2>&1 >/dev/null) || echo "conveyor: card $1: #$2 was split, and could not be held: ${x:0:300}" >&2
  # Its slices become its parts (GitHub sub-issues): umbrellas() closes it once each is closed or landed.
  # shellcheck disable=SC2046 # one issue number a word
  if jq -e '.cards' <<<"$split" >/dev/null; then x='are cards with no GitHub issue and build it, and this issue is not built itself. It stays open and held until each of them lands or is already done on main'
  elif x=$(attachparts "$2" $(jq -r '.filed[]' <<<"$split")); then x='are its sub-issues and build it, and this issue is not built itself. It stays open and held until each of them is closed or lands'
  else echo "conveyor: card $1: #$2 was split; its slices could not all be made its sub-issues: $x" >&2
    x='build it, and this issue is not built itself. It stays open and held until each of them lands or is already done on main'; fi
  x=$(jq -r --argjson s "$size" --arg w "$x" '"Conveyor split this issue under the rule Split large issues. Its follow-ups below \($w); then Conveyor closes it.\n\nEach Done-when item and the follow-up that covers it:\n"
    + ([(.cards // (.filed | map("#\(.)"))) as $f | .slices | to_entries[] | .key as $k | .value.covers[] | {d: ., n: $f[$k]}] | sort_by(.d)
       | map("- D\(.d) (\($s.doneWhen[.d - 1] | .[0:160])): \(.n)") | join("\n"))' <<<"$split")
  gh_write issue comment "$2" --body "$x" >/dev/null 2>&1 || echo "conveyor: card $1: #$2 was split; no comment could be added to it" >&2
  record "$1" "$2" closed ok "$(jq -c '{followups: .filed, reason: "split into \((.cards // (.filed | map("#\(.)"))) | join(", ")) under the rule Split large issues: this issue is their umbrella, held, and Conveyor closes it when each of them lands or is already done on main"}' <<<"$split")"
  return 1
}
# The slices of a split, filed as follow-ups of <issue>: its priority, area and type labels and its milestone, the
# follow-up label, a body that opens "Follow-up of #<issue>", its Done-when items, the items of the parent it covers,
# and a `Depends on: #N` line for each slice it depends on. A slice of a grown change (one with files, growcheck())
# names the files of the change it builds again in place of the items it covers, and depends on <issue> too, as it
# builds on the change that lands it. They start where the parent is (splitplace()): held when the control record
# holds it, else queued. Prints {filed: their numbers, held: whether they start held}; when one cannot be filed, or
# they cannot be placed, prints why and fails, the ones filed before it withdrawn (the reason names each whose close
# failed: it may still be open, and the exit is 2). <made> (splitmade()) gives the slices <card> filed before it
# stopped: they are kept, and only the others are filed. One kept that is open waits on each slice now in a place it
# depends on that its `Depends on:` does not name (`control depends`: filed in place of a withdrawn one, by this card or
# one that stopped before the edit); else it prints why and the exit is 2, nothing withdrawn. Bug: a kept slice that
# named only the closed one could start before the one in that place landed, also after a second restart.
splitfile() { # <card> <issue json> <slices json> <1: the slices take the parent's place in the pick order; 0: not> [<made json>]
  local n k i out num nums=() add open='' more=() body held w r=1 pa sa t
  n=$(jq -r .number <<<"$2") && k=$(jq length <<<"$3") || { echo "the slices could not be read"; return 1; }
  mapfile -t more < <(jq -r --arg a "$AREA" --arg t "$TYPE" --argjson p "$PRIOS" '(.labels // [] | map(.name)
      | map(select(($a != "" and startswith($a)) or . == $t or IN($p[]))) | unique[] | "--label", .), (.milestone.title // empty | "--milestone", .)' <<<"$2")
  pa=$(jq -r --arg a "$AREA" '.labels // [] | map(.name | select(startswith($a))) | .[0] // empty' <<<"$2")
  for ((i = 0; i < k; i++)); do
    num=$(jq -r --argjson i "$i" '.[$i] // empty' <<<"${5:-[]}") || { echo "the slices filed before could not be read"; return 1; }
    if [ -n "$num" ]; then
      # The slices now in the places it depends on that its `Depends on:` lines do not name (an open one; a closed one
      # is done), read from the open issues (DEPS needs).
      out='the open issues could not be read'
      # shellcheck disable=SC2086 # one issue number a word
      add=$(jq -c --argjson i "$i" --argjson s "$(jq -cn '$ARGS.positional | map(tonumber)' --args "${nums[@]}")" '[.[$i].dependsOn // [] | .[] | $s[. - 1]]' <<<"$3") \
        && { [ "$add" = '[]' ] || { { [ -n "$open" ] || open=$(openissues number,body); } \
          && add=$(jq -r --argjson x "$num" --argjson a "$add" "$DEPS"'.[] | select(.number == $x) | $a - needs | .[]' <<<"$open") \
          && { [ -z "$add" ] || out=$(depends "$num" add $add 2>&1 >/dev/null); }; }; } \
        || { out=${out//$'\n'/; }; echo "slice $((i + 1)), #$num, filed before, could not be made to wait on the slices in the places it depends on: ${out:0:300}"; return 2; }
      nums+=("$num"); continue
    fi
    # A parent with no area label: each slice has the area of the first file it builds again, else of the file its body
    # names, else the map's other (filearea(), lib/areas.sh).
    sa='' t=$(jq -r --argjson i "$i" '.[$i].files[0]? // empty' <<<"$3")
    body=$(jq -r --argjson i "$i" --argjson k "$k" --arg c "$1" --arg area "$AREA" --argjson sl "$3" --argjson nums "$(jq -cn '$ARGS.positional | map(tonumber)' --args "${nums[@]}")" \
      '. as $iss | ('"$SPLITSIZE"' | .doneWhen) as $dw | $iss | .number as $n | $sl[$i] as $s
      | if $s.files == null then
          "Follow-up of #\($n): slice \($i + 1) of \($k). Conveyor card \($c) split #\($n) under the rule Split large issues. #\($n) stays open and held until each of its slices lands or is already done on main.\n\n"
          + "## The Done-when items of #\($n) this slice covers\n" + ($s.covers | map("- D\(.): \($dw[. - 1])") | join("\n"))
          + (if $s.dependsOn == [] then "" else "\n\n" + ($s.dependsOn | map("Depends on: #\($nums[. - 1])") | join("\n")) end)
        else
          "Follow-up of #\($n): slice \($i + 1) of \($k). Conveyor card \($c) moved this part out of its change for #\($n), which grew past the pack'"'"'s split.growFiles files, under the rule Split large issues: #\($n) lands without it.\n\n"
          + "## The files of that change this slice builds again\n" + ($s.files | map("- " + .) | join("\n"))
          + "\n\nDepends on: #\($n)" + ($s.dependsOn | map("\nDepends on: #\($nums[. - 1])") | join(""))
        end
        + "\n\n## Done when\n" + ($s.doneWhen | map("- " + .) | join("\n"))' <<<"$2") \
      && { [ -n "$pa" ] || sa=$(filearea "" "${t:-$body}") || sa=''; } \
      && out=$(gh_write issue create --title "$(jq -r --argjson i "$i" '.[$i].title' <<<"$3")" --label "$FOLLOWUP" "${more[@]}" ${sa:+--label "$sa"} --body "$body" 2>&1) \
      && num=$(grep -oE '/issues/[0-9]+' <<<"$out" | tail -n 1) && num=${num##*/} && [ -n "$num" ] \
      || { w=$(splitwithdraw "$n" "${nums[@]}") || w="; Conveyor could not confirm that GitHub closed the slices filed before it ($w): they may still be open" r=2
           echo "slice $((i + 1)) was not filed: ${out:0:300}$w"; return "$r"; }
    nums+=("$num")
  done
  held=$(locked splitplace "$n" "$4" "${nums[@]}") && [[ $held =~ ^(true|false)$ ]] \
    || { w=$(splitwithdraw "$n" "${nums[@]}") || w="; Conveyor could not confirm that GitHub closed the slices filed ($w): they may still be open" r=2
         echo "the control record could not be read or written, so the slices could not be held or queued as their issue is$w"; return "$r"; }
  jq -cn --argjson h "$held" '{filed: ($ARGS.positional | map(tonumber)), held: $h}' --args "${nums[@]}"
}
# The slices of a split as cards with no GitHub issue (rules.splitissues false: tcadd(), lib/testaction.sh), in the
# place of splitfile()'s issues: the same bodies, each `Depends on:` line naming the card id of an earlier slice, the
# parent's priority, area and type labels and the follow-up label as the stand-in issue's, held when the control record
# holds <issue>. Prints {filed: [], cards: their ids, held: whether they start held}; when one cannot be made, prints
# why and fails, the ones made before it taken out again (splitdrop(): when one stays, the exit is 2). <made>: as
# splitfile()'s.
splitcards() { # <card> <issue json> <slices json> <unused: 1 or 0, as splitfile()> [<made json>]
  local n k i body held ids=() id x labels
  n=$(jq -r .number <<<"$2") && k=$(jq length <<<"$3") || { echo "the slices could not be read"; return 1; }
  held=$(jq -r --argjson n "$n" 'if .held | index($n) != null then "held" else "" end' <<<"$(ctl 2>/dev/null)") || held=''
  labels=$(jq -c --arg a "$AREA" --arg t "$TYPE" --arg f "$FOLLOWUP" --argjson p "$PRIOS" '(.labels // [] | map(.name) | map(select(($a != "" and startswith($a)) or . == $t or IN($p[]))) | unique) + [$f]' <<<"$2") \
    || { echo "the labels of #$n could not be read"; return 1; }
  for ((i = 0; i < k; i++)); do
    id=$(jq -r --argjson i "$i" '.[$i] // empty' <<<"${5:-[]}") || { echo "the slices made before could not be read"; return 1; }
    [ -z "$id" ] || { ids+=("$id"); continue; }
    body=$(jq -r --argjson i "$i" --argjson k "$k" --arg c "$1" --arg area "$AREA" --argjson sl "$3" --argjson ids "$(jq -cn '$ARGS.positional' --args "${ids[@]}")" \
      '. as $iss | ('"$SPLITSIZE"' | .doneWhen) as $dw | .number as $n | $sl[$i] as $s
      | "Follow-up of #\($n): slice \($i + 1) of \($k). Conveyor card \($c) split #\($n) under the rule Split large issues. #\($n) stays open and held until each of its slices lands or is already done on main.\n\n"
        + "## The Done-when items of #\($n) this slice covers\n" + ($s.covers | map("- D\(.): \($dw[. - 1])") | join("\n"))
        + (if $s.dependsOn == [] then "" else "\n\n" + ($s.dependsOn | map("Depends on: \($ids[. - 1])") | join("\n")) end)
        + "\n\n## Done when\n" + ($s.doneWhen | map("- " + .) | join("\n"))' <<<"$2") \
      && id=$(tcadd "" "$(jq -r --argjson i "$i" '.[$i].title' <<<"$3")" "$body" "$held" "Split part of #$n" "$labels" "$n") \
      || { x=$(splitdrop "${ids[@]}") || { echo "slice $((i + 1)) was not made a card, and of the cards made before it, $x"; return 2; }
           echo "slice $((i + 1)) was not made a card"; return 1; }
    ids+=("$id")
  done
  jq -cn --argjson h "$([ -n "$held" ] && echo true || echo false)" '{filed: [], cards: $ARGS.positional, held: $h}' --args "${ids[@]}"
}
# Under the lock: the slices of <issue> start where it is now. The control record is read here, not taken from the
# card: the card's copy is the one the loop read at the start of its turn, and an owner's release of the issue just
# before its pick is not in it (#782). Held when the record holds <issue>, dated as `control hold` dates them; and
# with <order> 1, when the pick order names <issue>, the slices stand in its place there, in their order. Prints
# whether they are held (true or false).
splitplace() { # <issue> <order: 1 or 0> <slice>...
  local n=$1 o=$2 c new h; shift 2
  c=$(ctl) && new=$(jq -c --argjson n "$n" --argjson o "$o" '($ARGS.positional | map(tonumber)) as $s
    | (if .held | index($n) != null then .held = (.held + $s | unique) else . end)
    | if $o == 1 and (.order | index($n) != null) then .order |= (index($n) as $i | .[:$i] + $s + (.[$i + 1:] - $s)) else . end' --args "$@" <<<"$c") \
    && h=$(jq -r --argjson n "$n" '.held | index($n) != null' <<<"$new") && ctlput "$c" "$new" || return 1
  [ "$h" != true ] || movedlocked movedhold hold "$new" "$@"
  echo "$h"
}
# Under the lock: when the pick order no longer names <issue> and names one of its <slice>s that splitend() withdraws
# (splitplace() put them in its place), <issue> takes the place of the first of them, and they leave the order. Bug: a plan ended after
# splitplace() left the slices' place to closed issues, so the slices of the next split could not take #<issue>'s place.
splitslot() { # <issue> <slice>...
  local n=$1 c new; shift
  c=$(ctl) && new=$(jq -c --argjson n "$n" '($ARGS.positional | map(tonumber)) as $s
    | if .order | index($n) != null then . else ([.order // [] | to_entries[] | select(.value | IN($s[])) | .key] | first) as $i
      | if $i == null then . else .order |= .[:$i] + [$n] + (.[$i:] - $s) end end' --args "$@" <<<"$c") && ctlput "$c" "$new"
}
# Takes each card <id> out of the queue (tcdrop()). When one stays in it (a card picked it first, or it could not be
# taken out), or the queue cannot be read after, prints which (or that) and fails.
splitdrop() { # <id>...
  local x
  for x; do tcdrop "$x"; done
  [ $# != 0 ] || return 0
  x=$(jq -r --argjson s "$(jq -cn '$ARGS.positional' --args "$@")" '[.cards[] | select(.id | IN($s[])) | .id] | join(", ")' "$TACARDS" 2>/dev/null) \
    || { echo "the queue could not be read after, so they may still be in it"; return 1; }
  [ -z "$x" ] || { echo "$x stays in it: a card picked it first, or it could not be taken out"; return 1; }
}
# The issues <slice> that a card took (a card of its own, in the card records or endedrecs(), not blocked): prints
# "a card took #N, #M already", nothing when none; fails when the records cannot be read.
splitbusy() { # <slice>...
  local x l b=()
  for x; do
    l=$({ endedrecs && stdb ask issue cards "$x"; } 2>/dev/null) && l=$(jq -Rn --argjson n "$x" '[inputs | fromjson? | objects | select(.issue == $n)] | group_by(.card) | any(all(.step != "blocked"))' <<<"$l") || return 1
    [ "$l" != true ] || b+=("#$x")
  done
  [ ${#b[@]} = 0 ] || { printf -v x '%s, ' "${b[@]}"; echo "a card took ${x%, } already"; }
}
# Under the pick's lock (locked()): when no card took one of the slices <slice> (splitbusy()), they are held and give
# <issue> back their place in the pick order (splitslot()), before they close. A pick after it, also from an open list
# asked before the close (turnask(), lib/run.sh), takes no held issue; a Board refresh after the closes (adopt()) drops
# their pins, and the place with them. Prints the why's end (the place not given back, or nothing); fails with why.
splitfence() { # <issue> <slice>...
  local n=$1 x; shift
  x=$(splitbusy "$@") && [ -z "$x" ] || { echo "${x:-the card records could not be read, so whether a card took one of its slices is not known}"; return 1; }
  x=$(control hold "$@" 2>&1 >/dev/null) || { echo "they could not be held back from the pick: ${x:0:300}"; return 1; }
  splitslot "$n" "$@" || echo "; the control record could not be read or written, so #$n did not get back their place in the pick order"
}
# Blocks card <card> of <issue> with no split line, as slices of a split may stay in the queue (<why>): built whole
# beside them, the issue could build their work twice. The plan stays unrecorded, so the next card reads it again.
splitstop() { # <card> <issue> <why>
  block "$1" "$2" "$CARDS/$1" "split: $3; built whole beside them, #$2 could build their work twice"
}
# Closes each <slice> as not planned. When the close of one or more fails, prints each of them (#N, #M) and fails: a
# failed close is not known to have closed the issue, so it may still be open.
splitwithdraw() { # <issue> <slice>...
  local n=$1 x f=(); shift
  for x; do gh_write issue close "$x" --reason "not planned" --comment "Conveyor: the split of #$n could not be filed whole, so this slice is withdrawn and is not built." >/dev/null 2>&1 || f+=("#$x"); done
  [ ${#f[@]} = 0 ] || { printf -v x '%s, ' "${f[@]}"; echo "${x%, }"; return 1; }
}
# Ends the plan of card <card> for <issue> that no split line records (splitcheck()): the slices <made> (splitmade())
# it filed are held and give <issue> back their place in the pick order (splitfence()), then they are withdrawn
# (splitwithdraw()); or its cards with no GitHub issue are taken out of the queue (splitdrop()). Prints the end of the
# split line's why that says so. Fails when one may stay in the queue (GitHub did not confirm a close; a card picked
# it first, given back by `retry` or not; the queue could not be read), or when a card took one of the issues
# (splitbusy(): none is closed then, as a close does not stop that card): the caller blocks the card (splitstop()).
# Bugs: the issue was built whole beside a slice left in the queue, or beside one whose card had started (also one a
# pick took after the last check, from an open list it asked before the close); the place was lost.
splitend() { # <card> <issue> <splitfile or splitcards> <made json>
  local s=() w x f r=0
  mapfile -t s < <(jq -r '.[] // empty' <<<"$4")
  w="; card $1 stopped before it filed the whole split it planned for #$2"
  if [ ${#s[@]} = 0 ]; then w+=", and it had filed no slice"
  elif [ "$3" = splitfile ]; then
    f=$(locked splitfence "$2" "${s[@]}") || { echo "$w; ${f:-the lock of the card records could not be taken, so whether a card took one of its slices is not known}, so none is withdrawn"; return 1; }
    printf -v x '#%s, ' "${s[@]}"; w+=", so its slices ${x%, } are withdrawn$f"
    x=$(splitwithdraw "$2" "${s[@]}") || { w+="; Conveyor could not confirm that GitHub closed $x: they may still be open"; r=1; }
  else
    printf -v x '%s, ' "${s[@]}"; w+=", so its cards ${x%, } are taken out of the queue"
    x=$(splitdrop "${s[@]}") || { w+="; $x"; r=1; }
  fi
  echo "$w"; return "$r"
}
# The newest split that a card of <issue> planned (the plan on its start line of the filing, splitcheck()) and that no
# split line records: neither the card's own line nor that of a card that finished it (split.resumed). Prints
# "<card>\t<plan json>", nothing when there is none; fails when the records cannot be read.
splitplan() { # <issue>
  { recs && olds; } 2>/dev/null | grep -F -e '"plan"' -e '"split"' | jq -Rnr --argjson n "$1" '[inputs | fromjson? | objects | select(.issue == $n)]
    | [.[] | select(.step == "split") | .card, (.split.resumed // empty)] as $done
    | [.[] | select(.step == "start" and .plan != null and (.card | IN($done[]) | not))] | last // empty | "\(.card)\t\(.plan | tojson)"'
  # Kept at once: the first test replaces PIPESTATUS. Bug: the second read an unset item, and set -u failed the call.
  local s=("${PIPESTATUS[@]}"); [ "${s[0]}" = 0 ] && [ "${s[2]}" = 0 ]
}
# The lines of an issue's body (its input) that are its own text, each with its \r and trailing blanks cut: those not
# in a fenced code block (``` or ~~~) and not quoted (>). splitmade() and growopen() find a slice's notes there, on any
# line: an owner may write above them, and an issue that quotes a slice is not that slice. Bug: an open issue that
# quoted a grown slice in a code block was taken for it, and closed.
BODYLINES='def bodylines: . // "" | split("\n") | map(rtrimstr("\r") | sub("\\s+$"; ""))
  | reduce .[] as $l ({f: false, o: []}; if $l | test("^\\s*(```|~~~)") then .f |= not elif .f or ($l | test("^\\s*>")) then . else .o += [$l] end) | .o;'
# The slices of <issue> that card <card> filed or made for its plan before it stopped (splitfile(), splitcards()): the
# issues, open or closed, with the follow-up label or not, or the queue's cards with no GitHub issue, picked or not,
# with a line of their own text (BODYLINES) that names <card> as the card that split <issue>. Prints a JSON list with
# the issue number or card id of each slice by its place (null: not filed yet). A slice that is already picked or built
# is kept as it is, so no card builds a slice twice; one closed as not planned (splitwithdraw(): the card withdrew it
# when a later slice could not be filed) is not filed yet, as it was never built. Bugs: a withdrawn slice counted as
# filed, so the umbrella closed once the others landed, and its work was never built; the list stopped at the newest
# 1000 follow-ups, and a slice older than them was filed again; an owner's edit (the label taken off, a heading above
# that line) hid a slice, and it was filed again, or left in the queue. When they cannot be read, prints why and fails.
splitmade() { # <card> <issue> <splitfile or splitcards>
  local re="^\\s*Follow-up of #$2: slice (?<i>[0-9]+) of [0-9]+\\. Conveyor card (?<c>[^ ]+) split #$2 under the rule Split large issues\\." l lim=1000 s x d=()
  if [ "$3" = splitcards ]; then
    l='[]'; [ ! -s "${TACARDS:-}" ] || l=$(jq -ce '.cards | arrays | map({number: .id, body})' "$TACARDS") \
      || { echo "the queue of cards with no GitHub issue could not be read, so the slices that card $1 made for #$2 are not known"; return 1; }
  else
    while :; do # a full page means there may be more: ask again for ten times as many until the answer is short
      l=$(gh issue list --state all --limit "$lim" --json number,body,state) && s=$(jq length <<<"$l") \
        || { echo "the issues could not be read, so the slices that card $1 filed for #$2 are not known"; return 1; }
      [ "$s" -ge "$lim" ] || break; lim=$((lim * 10))
    done
  fi
  l=$(jq -c --arg re "$re" --arg c "$1" "$BODYLINES"'[.[] | . as $e | [.body | bodylines[] | capture($re)?] | .[0] // empty | select(.c == $c)
      | {i: (.i | tonumber), v: $e.number, closed: ($e.state == "CLOSED")}]' <<<"$l") \
    || { echo "the slices that card $1 filed for #$2 could not be read"; return 1; }
  # Why each closed one was closed: GitHub's list does not give it.
  for x in $(jq -r '.[] | select(.closed) | .v' <<<"$l"); do
    s=$(gh api graphql -F owner='{owner}' -F repo='{repo}' -F number="$x" -f query='query($owner: String!, $repo: String!, $number: Int!) {
      repository(owner: $owner, name: $repo) { issue(number: $number) { stateReason } } }' 2>/dev/null | jq -er '.data.repository.issue.stateReason | strings' 2>/dev/null) \
      || { echo "why #$x was closed could not be read, so whether card $1 withdrew it is not known"; return 1; }
    [ "$s" != NOT_PLANNED ] || d+=("$x")
  done
  jq -c --argjson d "$(jq -cn '$ARGS.positional | map(tonumber)' --args "${d[@]}")" 'reduce (.[] | select(.v | IN($d[]) | not)) as $s ([]; .[$s.i - 1] = $s.v)' <<<"$l" \
    || { echo "the slices that card $1 filed for #$2 could not be read"; return 1; }
}
# A change that grew while it was built (#448). card() calls growcheck() before each review of a card of an issue of
# its own (not a main-red fix card nor a branch), until it has asked the judge once (it sets the caller's grown). With
# the rule Shadow or On, a card whose issue is no follow-up, and whose staged change holds more files than the pack's
# split.growFiles (documentation, *.md, left out), the judge is given the issue, the files with their lines added and
# removed, and the change (its first GROW_DIFF characters), once and SPLIT_TIMEOUT at most. It answers keep, or the
# core files that stay on the card and 1 to 3 slices, each a title, Done-when items and the files it takes (GROWASK).
# An answer is used only when it holds to the rules (GROWREAD): every file of the change is in exactly one part, the
# core holds one at least, and a slice depends only on slices before it.
# The card's grown line records it: result split or kept, grown {mode, files (the count before), limit, verdict
# (keep, split, invalid, failed), why, core, slices ({title, doneWhen, files, dependsOn}), filed and after (On: the
# issues filed, and the count once their files are dropped), withdrawn (On: the open slices of earlier cards of the
# issue closed in their place, growprior(); when one cannot be closed, those closed before it), answer}, and model. In Shadow that is all. On, each open
# issue that waits on an earlier slice the new ones replace is made to wait on the issue too (growwait()), those earlier
# slices are closed (growclose()), then the slices are filed as follow-ups of the issue (splitfile(), held or
# queued as the issue is, and each held when one it replaces was; an open issue that waited on one of those waits on
# the new ones that take its files too, growafter(); a run limited by --only to the issue takes them too, jq/upnext.jq),
# their files are put back to what HEAD has (a file the change added is removed), and one fix session (GROWFIX) makes
# what is left work alone; the card then goes on to its review. Slices that cannot be filed, earlier slices that cannot
# be read or closed, or a hold or `Depends on:` that cannot be put on the new slices (they are withdrawn), leave the
# change whole, and the line says why. When GitHub does not confirm the close of a slice it filed, the card is blocked
# (growstop()).
GROW_DIFF=60000
GROWASK='A coding session built the change below for the issue below. The change has grown to <files> files (documentation
left out), past the <limit> files the project allows one change: a change this large is slow to review and to test.
Decide whether to keep only its core on this card, and move the rest into 1 to 3 follow-up issues (slices), each
built later as a change of its own.
The rules of a split:
- The core is the part the issue needs. It stays a complete change that works on its own and meets every Done-when
  item of the issue.
- A slice is a part the issue does not need: a complete change that works on its own once the core has landed. It
  has a title, Done-when items of its own, and the files of the change it takes (those files go back to what main
  has on this card, and the slice builds them again).
- Each file of the change is in exactly one part: the core or one slice. The core has one file at least.
- A slice that changes the same code as an earlier slice depends on it: give the numbers of the earlier slices it
  depends on (1 is the first slice).
Keep the change whole when its parts cannot each work on their own. When you are not sure, keep it.
Answer with exactly one JSON object and nothing else, one of:
{"verdict": "keep", "why": "<one line>"}
{"verdict": "split", "why": "<one line>", "core": ["<file>"], "slices": [{"title": "<title>", "doneWhen": ["<item>"], "files": ["<file>"], "dependsOn": [<number of an earlier slice>]}]}'
# The judge's answer (its input, raw) against those rules, $files the change's files: as SPLITREAD reads one.
GROWREAD='def nums: type == "array" and all(.[]; type == "number" and . == floor);
  def strs: type == "array" and length > 0 and all(.[]; type == "string" and test("\\S"));
  def twice: group_by(.) | map(select(length > 1) | .[0]);
  . as $raw | (index("{")) as $s | (rindex("}")) as $e | select($s != null and $e != null and $s < $e) | .[$s:$e + 1] | fromjson? | objects
  | (.why | if type == "string" then .[0:300] else "" end) as $why
  | (if .verdict == "keep" then null
     elif .verdict != "split" then "the verdict is neither keep nor split"
     elif (.slices | type) != "array" or (.slices | length) < 1 or (.slices | length) > 3 then "not 1 to 3 slices"
     elif (.core | strs | not) then "the core has no files"
     elif any(.slices[]; (.title | type) != "string" or (.title | test("\\S") | not)) then "a slice has no title"
     elif any(.slices[]; .doneWhen | strs | not) then "a slice has no Done-when items of its own"
     elif any(.slices[]; .files | strs | not) then "a slice takes no files"
     elif any(.slices | to_entries[]; .key as $k | .value.dependsOn // [] | (nums | not) or any(.[]; . < 1 or . > $k)) then "a slice depends on a slice that is not before it"
     else [.core[], .slices[].files[]] as $all
       | if ($all - $files) != [] then "it names \(($all - $files) | unique | join(", ")), which the change does not hold"
         elif ($files - $all) != [] then "no part holds \(($files - $all) | join(", "))"
         elif ($all | twice) != [] then "more than one part holds \($all | twice | join(", "))" else null end end) as $bad
  | if $bad != null then {verdict: "invalid", why: $bad, answer: $raw[0:2000]}
    elif .verdict == "keep" then {verdict: "keep", why: $why}
    else {verdict: "split", why: $why, core: (.core | unique), slices: [.slices[] | {title: (.title | gsub("\\s+"; " ") | .[0:200]), doneWhen: (.doneWhen | map(gsub("\\s+"; " "))),
      files: (.files | unique), dependsOn: (.dependsOn // [] | unique)}]} end'
GROWFIX='# The change was split for its size
The change grew past the files the project allows one change. The judge kept its core on this card and moved the
parts below into follow-up issues, and the engine put their files back to what main has. Make the change that is left
complete and working on its own: fix what still uses the parts moved out. Do not build those parts again here; their
issues build them. Change nothing else.'
# The files of the staged change of <worktree>, documentation (*.md) left out, as a JSON list.
growfiles() { git -C "$1" add -A && git -C "$1" diff --cached --no-renames --name-only HEAD -- . ':!*.md' | jq -Rsc 'split("\n") | map(select(. != ""))'; }
growcheck() { # <card> <issue> <worktree> <issue json> <the sessions' prompt>: 0 when the card goes on as it was; 2 when it goes on split; 1 when it blocked
  local c=${CARDCTL:-} rule lim files k p d ans model='' v g nums f t after u o x w
  [ "$2" != 0 ] || return 0
  [ -n "$c" ] || c=$(ctl 2>/dev/null) || return 0
  rule=$(jq -r '.rules.split // "off"' <<<"$c" 2>/dev/null)
  [ "$rule" = shadow ] || [ "$rule" = on ] || return 0
  ! jq -e --arg fu "$FOLLOWUP" 'any(.labels[]?; .name == $fu)' <<<"$4" >/dev/null 2>&1 || return 0
  packget split.growFiles lim && files=$(growfiles "$3") && k=$(jq length <<<"$files") || return 0
  [ "$k" -gt "$lim" ] || return 0
  # shellcheck disable=SC2034 # card()'s local: its later reviews ask no more
  grown=1
  p=${GROWASK//'<files>'/$k}; p=${p//'<limit>'/$lim}
  p+=$'\n\n'$(jq -r '"# The issue: #\(.number) \(.title // "")\n\n\(.body // "")"' <<<"$4")
  p+=$'\n\n# The files of the change (lines added, lines removed)\n'$(git -C "$3" diff --cached --no-renames --numstat HEAD -- . ':!*.md')
  d=$(git -C "$3" diff --cached --no-renames HEAD -- . ':!*.md')
  p+=$'\n\n# The change\n'"${d:0:$GROW_DIFF}"; [ "${#d}" -le "$GROW_DIFF" ] || p+=$'\n(the rest of the change is left out)'
  if ! splitcall "$c" "$p"; then v=$(jq -cn --arg r "$ans" '{verdict: "failed", why: $r}')
  else v=$(jq -Rsc --argjson files "$files" "$GROWREAD" <<<"$ans" 2>/dev/null)
    [ -n "$v" ] || v=$(jq -cn --arg a "${ans:0:2000}" '{verdict: "invalid", why: "the answer held no JSON object", answer: $a}'); fi
  g=$(jq -c --arg m "$rule" --argjson k "$k" --argjson l "$lim" '{mode: $m, files: $k, limit: $l} + .' <<<"$v") || return 0
  if [ "$rule" = on ] && [ "$(jq -r .verdict <<<"$g")" = split ]; then
    if ! u=$(growprior "$2" "$(jq -c .slices <<<"$g")" "$files" "$1") || ! o=$(jq -c 'map(select(.open) | .n)' <<<"$u"); then
      g=$(jq -c --arg r "$u" '.why += "; no slice is filed, so the change is kept whole: \($r)"' <<<"$g")
    elif ! x=$(growwait "$2" "$(jq -c 'map(.n)' <<<"$u")"); then
      g=$(jq -c --arg r "$x" '.why += "; no slice is filed, so the change is kept whole: \($r)"' <<<"$g")
    # stop (halt(), lib/run.sh) leaves the card to finish from here: its slices are being filed. Its start line names
    # the open slices it closes first (replaces: growgone() reads it after a stop between the closes and the filing),
    # on disk (RECSYNC, append(), lib/records.sh).
    elif ! RECSYNC=1 began "$1" "$2" file "$(jq -c '{replaces: map(select(.open) | {n, files})}' <<<"$u")"; then
      g=$(jq -c '.why += "; no slice is filed, so the change is kept whole: the start of the filing could not be recorded"' <<<"$g")
    elif ! nums=$(growclose "$1" "$2" "$o"); then
      g=$(jq -c --arg r "${nums%%$'\n'*}" --argjson c "${nums#*$'\n'}" '.why += "; no slice is filed, so the change is kept whole: \($r)" | if $c == [] then . else . + {withdrawn: $c} end' <<<"$g")
    elif g=$(jq -c --argjson u "$o" 'if $u == [] then . else . + {withdrawn: $u} end' <<<"$g") && nums=$(splitfile "$1" "$4" "$(jq -c .slices <<<"$g")" 0); x=$?; [ "$x" != 0 ]; then
      [ "$x" != 2 ] || { growstop "$1" "$2" "$3" "$g" "the slices could not be filed whole: $nums"; return 1; } # some may stay open
      g=$(jq -c --arg r "$nums" '.why += "; the slices could not be filed, so the change is kept whole: \($r)"' <<<"$g")
    elif nums=$(jq -c .filed <<<"$nums") && ! x=$(growafter "$2" "$u" "$(jq -c .slices <<<"$g")" "$nums"); then
      # What held the earlier slices back could not be put on the new ones: they are withdrawn, and the change is kept
      # whole. Bug: a new slice the owner's hold or a `Depends on:` should have held back went in the queue.
      # shellcheck disable=SC2046 # one issue number a word
      w=$(splitwithdraw "$2" $(jq -r '.[]' <<<"$nums")) || { growstop "$1" "$2" "$3" "$g" "$x; GitHub did not confirm the close of the slices filed $w"; return 1; }
      g=$(jq -c --arg r "$x" --argjson f "$nums" '.why += "; the slices filed (\($f | map("#\(.)") | join(", "))) are withdrawn, so the change is kept whole: \($r)"' <<<"$g")
    else
      # Each file a slice takes goes back to what HEAD has; one the change added is removed.
      while IFS= read -r f; do
        if git -C "$3" cat-file -e "HEAD:$f" 2>/dev/null; then git --literal-pathspecs -C "$3" restore --source=HEAD --staged --worktree -- "$f"
        else git --literal-pathspecs -C "$3" rm -qf -- "$f"; fi >/dev/null 2>&1 \
          || { record "$1" "$2" grown split "$(jq -c --argjson f "$nums" --arg m "$model" '{grown: (. + {filed: $f})} + (if $m != "" then {model: $m} else {} end)' <<<"$g")"
               block "$1" "$2" "$3" "split for its size: the engine could not drop $f from the change; its slices are filed as $(jq -r 'map("#\(.)") | join(", ")' <<<"$nums")"; return 1; }
      done < <(jq -r '.slices[].files[]' <<<"$g")
      after=$(growfiles "$3" | jq length) || after=null
      g=$(jq -c --argjson f "$nums" --argjson a "${after:-null}" '. + {filed: $f, after: $a}' <<<"$g")
    fi
  fi
  record "$1" "$2" grown "$(jq -r 'if .verdict == "split" then "split" else "kept" end' <<<"$g")" \
    "$(jq -c --arg m "$model" '{grown: .} + (if $m != "" then {model: $m} else {} end)' <<<"$g")"
  jq -e '.filed' <<<"$g" >/dev/null || return 0
  began "$1" "$2" fix
  t=$(session "$3" "$5"$'\n\n'"$GROWFIX"$'\n'"$(jq -r '[.filed, .slices] | transpose[] | "- #\(.[0]) \(.[1].title): \(.[1].files | join(", "))"' <<<"$g")" fix) \
    || { block "$1" "$2" "$3" "fix: $t"; return 1; }
  checked "$1" "$2" "$3" "$4" "$5" fix "$(jq -c --arg r "split for its size: $k files, $(jq -r .after <<<"$g") after; its slices are $(jq -r '.filed | map("#\(.)") | join(", ")' <<<"$g")" '. + {reason: $r}' <<<"$t")" || return 1
  return 2
}
# Before card <card> files <slices> (the slices of its grown change, whose files are <files>), the slices that earlier
# cards of <issue> filed for their grown changes and that are still open (growopen()), each with the files its body
# lists now (the owner may have edited them). Each one that takes
# a file of <slices> is printed ({n, files, open: true}), for growclose() to close before <slices> are filed: they build
# its part again, whole, with their own Done-when items and order. Bug (#1684): each card of an issue whose change
# grew again (a retry, a run after a block) filed the same part again: six open copies of one part in the queue. When
# the follow-ups cannot be read, or such a slice also takes a file that is not in <files> (closed, that part would be
# lost; left open, the files it shares would be built twice), prints why and fails: the card then files nothing.
# Those that an earlier card closed for its own slices and stopped before it filed them (growgone()) are printed too,
# with open false: what held them back holds <slices> (growafter()).
growprior() { # <issue> <slices json> <files json> <card>
  local l x g
  l=$(growopen "$1") && l=$(jq -c --argjson new "$2" '($new | map(.files[])) as $t | map(select(any(.files[]; IN($t[]))))' <<<"$l" 2>/dev/null) && [ -n "$l" ] \
    || { echo "the open follow-ups of #$1 could not be read, so the slices that earlier cards filed for it are not known"; return 1; }
  x=$(jq -r --argjson n "$1" --argjson all "$3" 'map(select(.files - $all != []))[0] // empty
    | "#\(.n), a slice that an earlier card filed for #\($n), also takes \(.files - $all | join(", ")), which this change does not have"' <<<"$l")
  [ -z "$x" ] || { echo "$x"; return 1; }
  g=$(growgone "$1" "$4") && [ -n "$g" ] || { echo "the card records of #$1 could not be read, so the slices that earlier cards closed for it are not known"; return 1; }
  jq -c --argjson g "$g" 'map(. + {open: true}) as $o | $o + [$g[] | select(.n | IN($o[].n) | not) | . + {open: false}]' <<<"$l"
}
# The slices that cards of <issue> other than <card> closed to file their grown change's slices in their place, and
# stopped before they filed them: the start line of such a filing names them (replaces: [{n, files}], growcheck()), and
# its card has no grown line, nor has the issue a grown line with filed slices after it: a JSON list of {n, files},
# each with the files no later card handed what held it back for (growresume()), and none with no file left. Bugs: the
# next card filed the slices with nothing of what held the closed ones back (an owner's hold, a `Depends on:`); a
# card that handed one file of a slice took it as handed whole, and the slice filed later for another file missed its
# hold and waits. Fails when the records cannot be read.
growgone() { # <issue> <card>
  local r
  r=$(stdb ask issue cards "$1" -- issue retried "$1" 2>/dev/null) && jq -sc --argjson n "$1" --arg me "$2" '[.[] | objects | select(.issue == $n)] | sort_by(.time) as $l
    | ([$l | to_entries[] | select(.value.step == "grown" and (.value.grown.filed | type) == "array") | .key] | last // -1) as $g
    | [$l[$g + 1:][] | select(.step == "grown") | .card] as $done | [$l[] | .handed // empty | .[]] as $h
    | [$l[$g + 1:][] | select(.step == "start" and (.replaces | type) == "array" and .card != $me and (.card | IN($done[]) | not)) | .replaces[]
      | .n as $k | .files -= [$h[] | select(.n == $k) | .files[]] | select(.files != [])] | unique_by(.n)' <<<"$r"
}
# As card <card> of <issue> starts, under each rule (splitcheck()): slices an earlier card closed for its grown change
# before it stopped (growgone()) hand what held them back to the open grown slices that take their files (growafter()).
# Prints the start line that records it ({of: file, handed: [{n, files: those an open slice takes}]}, nothing when
# none): so a later card does not hold them again after a release, and hands the other files on; fails with why. A stop
# after the filing and before growafter() left a slice queued with no hold or waits, and nothing put them there.
growresume() { # <card> <issue>
  local g l x
  g=$(growgone "$2" "$1") || { echo "the card records of #$2 could not be read, so the slices that earlier cards closed for it are not known"; return 1; }
  [ "$g" != '[]' ] || return 0
  l=$(growopen "$2") && l=$(jq -c --argjson g "$g" '[$g[].files[]] as $f | map(select(any(.files[]; IN($f[]))))' <<<"$l") \
    || { echo "the open follow-ups of #$2 could not be read, so the slices filed in place of $(jq -r 'map("#\(.n)") | join(", ")' <<<"$g") are not known"; return 1; }
  [ "$l" != '[]' ] || return 0
  g=$(jq -c --argjson l "$l" '[$l[].files[]] as $f | map(select(any(.files[]; IN($f[]))))' <<<"$g") \
    && x=$(growafter "$2" "$g" "$(jq -c 'map({files})' <<<"$l")" "$(jq -c 'map(.n)' <<<"$l")") || { echo "${x:-the slices could not be read}"; return 1; }
  jq -c --argjson l "$l" '[$l[].files[]] as $f | {of: "file", handed: map({n, files: [.files[] | select(IN($f[]))]})}' <<<"$g"
}
# The slices that cards of <issue> filed for their grown changes and that are still open: a JSON list of {n, files}.
# One is an open issue that a grown line of <issue> names as filed, or whose body is that of a grown slice of <issue>
# (splitfile(): a line that starts "Follow-up of #<issue>: slice ", and the note that the part was moved out of its
# change or the heading of its files, each on a line of its own text, BODYLINES, not in a quote or a code block; a
# slice filed just before a restart has no grown line), with or without the follow-up label. Its files are those its
# body lists now (the owner may have edited them; a path in backticks is the path), else those of its grown line.
# Bugs: an owner's edit hid an open slice (a heading or a note above its first line, a reworded note, the label taken
# off, backticks round a path), so its part was filed again. Fails when the open issues or the records cannot be read.
growopen() { # <issue>
  local l r
  r=$(stdb ask issue cards "$1" -- issue retried "$1" 2>/dev/null) && r=$(jq -sc --argjson n "$1" '[.[] | objects
      | select(.issue == $n and .step == "grown" and (.grown.filed | type) == "array") | [.grown.filed, .grown.slices // []] | transpose[]
      | select(.[0] != null) | {key: (.[0] | tostring), value: (.[1].files // [])}] | from_entries' <<<"$r" 2>/dev/null) && [ -n "$r" ] || return 1
  l=$(openissues number,body) && l=$(jq -c --argjson n "$1" --argjson r "$r" "$BODYLINES"'[.[]
      | (.body | bodylines) as $b | ($b | index("## The files of that change this slice builds again")) as $i
      | select($r[.number | tostring] or (any($b[]; test("^\\s*Follow-up of #\($n): slice "))
          and ($i != null or any($b[]; contains("moved this part out of its change for #\($n)")))))
      | (.number | tostring) as $k | {n: .number, files: ((if $i == null then [] else $b[$i + 1:] | (first(range(length) as $j | select(.[$j] | startswith("- ") | not) | $j) // length) as $e
          | .[:$e] | map(.[2:] | sub("^\\s+"; "") | ltrimstr("`") | rtrimstr("`")) end) | if . == [] then $r[$k] // [] else . end)}]' <<<"$l" 2>/dev/null) \
    && [ -n "$l" ] && printf '%s\n' "$l"
}
# The earlier slices <prior> (growprior()) of <issue> closed, before card <card> files the slices of its grown change
# in their place. Each file of <prior> is in the card's change (growprior()), and the change drops none of them before
# the new slices are filed: a stop or restart between the closing and the filing loses no part (the change still holds
# it whole), and never leaves an old and a new slice open for one part. Bug: the new slices were filed first, and a
# restart before the closing left two open copies of one part. When one cannot be closed, prints why, then on a second
# line the slices it closed before (a JSON list, for the grown line's withdrawn), and fails: the change is kept whole,
# and it has each file of the slices closed before.
growclose() { # <card> <issue> <prior json>
  local x c=()
  for x in $(jq -r '.[]' <<<"$3"); do
    gh_write issue close "$x" --reason "not planned" --comment "Conveyor card $1 built #$2 again, and its change grew again: the change of #$2 and the slices it files next take the files of this slice, so this copy is withdrawn." >/dev/null 2>&1 \
      || { echo "#$x, a slice that an earlier card filed for #$2, could not be closed, so no slice is filed in its place"; printf '%s\n' "${c[@]}" | jq -sc .; return 1; }
    c+=("$x")
  done
}
# Before the earlier slices <slices> of <issue> (growprior()) close, each other open issue that waits on one of them
# waits on <issue> too (`control depends`): their work lands with <issue>'s change or after it. Bug: a loop turn
# between the close and growafter() picked such an issue, as nothing open held it back. When one cannot be done,
# prints why and fails: the caller closes nothing.
growwait() { # <issue> <slices json>
  local o x e
  [ "$2" != '[]' ] || return 0
  o=$(openissues number,body) && o=$(jq -r --argjson n "$1" --argjson s "$2" "$DEPS"'.[] | .number as $x | select($x != $n and ($x | IN($s[]) | not))
      | needs as $w | select(any($s[]; IN($w[])) and ($n | IN($w[]) | not)) | $x' <<<"$o") \
    || { echo "the open issues could not be read, so one that waits on $(jq -r 'map("#\(.)") | join(", ")' <<<"$2") may not wait on #$1"; return 1; }
  for x in $o; do
    e=$(depends "$x" add "$1" 2>&1 >/dev/null) || { e=${e//$'\n'/; }; echo "#$x waits on a slice to be closed and could not be made to wait on #$1: ${e:0:300}"; return 1; }
  done
}
# Once the slices <new> of a grown change of <issue> (<slices>, by place) are filed in place of the earlier slices
# <prior> (growprior(): those growclose() closed, and those an earlier card closed, growgone()), what held each of
# <prior> back holds the new slices that take a file of it, and no other: they are held when it is (growhold()), and
# each open issue that depends on it depends on them too (`control depends`). Bugs: a replacement went in the queue
# though the owner held the slice it replaced (also when the hold came just before the close, or the card stopped
# between the close and the filing); a hold of one old slice held new slices of other files; an open slice that
# depended on a replaced one could start once the parent landed, before the replacement had. When one cannot be done,
# prints why and fails: the caller withdraws <new>, and the change is kept whole.
growafter() { # <issue> <prior json> <slices json> <new json>
  local m o x e
  m=$(jq -nc --argjson p "$2" --argjson s "$3" --argjson f "$4" '[$f, $s] | transpose | map(.[1].files as $t | {n: .[0], of: [$p[] | select(any(.files[]; IN($t[]))) | .n]})') \
    || { echo "the slices filed could not be read"; return 1; }
  x=$(locked growhold "$m" 2>&1 >/dev/null) || { x=${x//$'\n'/; }; echo "the slices filed could not be held as the slices they replace are: ${x:0:300}"; return 1; }
  [ "$2" != '[]' ] || return 0
  o=$(openissues number,body) && o=$(jq -r --argjson m "$m" "$DEPS"'[$m[].of[]] as $p | .[] | .number as $x | select($x | IN($p[]) | not) | needs as $w
      | [$m[] | select(any(.of[]; IN($w[]))) | .n] | select(. != []) | "\($x) \(join(" "))"' <<<"$o") \
    || { echo "the open issues could not be read, so one that waits on $(jq -r 'map("#\(.n)") | join(", ")' <<<"$2") may not wait on the slices filed"; return 1; }
  while read -r x e; do
    [ -n "$x" ] || continue
    # shellcheck disable=SC2086 # one issue number a word
    e=$(depends "$x" add $e 2>&1 >/dev/null) || { e=${e//$'\n'/; }; echo "#$x waits on a slice withdrawn and could not be made to wait on the slices filed: ${e:0:300}"; return 1; }
  done <<<"$o"
}
# Under the lock: each slice of <map> ([{n, of}], growafter()) is held (`control hold`) when the control record holds
# one of the slices it replaces (of). Read here, after those were closed: an owner's hold just before a close is in it,
# and a closed issue stays in held.
growhold() { # <map json>
  local c h
  c=$(ctl) && h=$(jq -r --argjson m "$1" '(.held // []) as $h | $m[] | select(any(.of[]; IN($h[]))) | .n' <<<"$c") || return 1
  # shellcheck disable=SC2086 # one issue number a word
  [ -z "$h" ] || control hold $h
}
# The grown line of card <card> with <grown json>, its why ended by <why>, and the card blocked: a slice it filed may
# stay open (GitHub did not confirm its close), and the change kept whole beside it could build its work twice. Reads
# growcheck()'s model.
growstop() { # <card> <issue> <worktree> <grown json> <why>
  record "$1" "$2" grown split "$(jq -c --arg r "$5" --arg m "$model" '{grown: (.why += "; \($r)")} + (if $m != "" then {model: $m} else {} end)' <<<"$4")"
  block "$1" "$2" "$3" "split for its size: $5; the change kept whole beside them could build their work twice"
}
# At a turn of the loop, outside the lock: each open issue of the list that is a parent (it has GitHub sub-issues,
# parts: openissues()) whose parts are each closed, or landed (its newest card has a landed or pushed line: landed()
# in DEPS, so a part built again after a landing waits for its new card), is closed, with a comment that names them
# and says which landed, and released from held. Push on or off alike: with push off (rules.push), a landed part stays
# open until the owner's push, and a split's slices are its parts, so its umbrella waited for that push.
# So is each open issue of the list with no parts (its slices were never attached as its sub-issues) that is the
# umbrella of a split (a split line with filed slices) whose slices each have a landed line, or a closed line (main
# already does it: ALREADY-DONE) that is not a shut one (SHUT: the owner closed it by hand; OWNSHUT: the owner shut the card).
# The slices that are cards with no GitHub issue (the split line's cards) count the same, by their card's records (TADONE):
# the cards of the slice's entry, a land-branch card that landed a branch named as the slice's card id included (slicetake(), lib/lane.sh).
# A card counts as landed only while its landed commit is on main (refs/heads/$BRANCH): with push off, the pack's
# defaultBranch changed to a branch without it leaves its parent open. A landed commit git no longer has (pruned once
# its branch went) is not on main either. With no open issue that has parts and no split line in the records, none
# can be closed: no program starts (it runs at each turn that asks GitHub).
umbrellas() { # <open issues, a json list>
  local k n s x m b cs off
  # The ended list (endedrecs(), lib/records.sh) first, as older cards: a part or slice whose card's lines went to the
  # archive is still landed or done.
  cs=$(endedrecs && echo && turncards) || return 0
  [[ $1 == *'"parts"'* || $cs == *'"split"'* ]] || return 0
  b=$(git rev-parse -q --verify "refs/heads/$BRANCH^{commit}") || { echo "conveyor: main ($BRANCH) could not be read; no parent is closed this turn" >&2; return 0; }
  off=$(jq -r 'select(.step == "landed") | .sha | strings' <<<"$cs" | offmain "$b") || return 0
  while IFS=$'\t' read -r k n s; do
    if [ "$k" = parts ]; then m="Conveyor: each part of this issue is closed or landed ($s), so this issue is closed too."
    else m="Conveyor: the last follow-up of this issue is done ($s), so each of its Done-when items is built."; fi
    x=$(gh_write issue close "$n" --comment "$m" 2>&1 >/dev/null) \
      || { echo "conveyor: #$n is $([ "$k" = parts ] && echo "a parent whose parts are all closed or landed" || echo "an umbrella whose follow-ups have all landed or are already done on main"), and it could not be closed (${x:0:300}); the next turn tries again" >&2; continue; }
    CONVEYOR_RELEASEBY=closed locked control release "$n" >/dev/null 2>&1 || :
  done < <(jq -rs --slurpfile open <(printf '%s' "$1") --rawfile off <(printf '%s' "$off") --arg shut "$SHUT" --arg own "$OWNSHUT" --arg eng "$ENGSHUT" "$DEPS"'$open[0] as $open
    # A card whose landed commit main does not hold: its landed and pushed lines are left out.
    | ($off | split("\n") - [""]) as $off | ([.[] | select(.step == "landed" and (.sha | IN($off[]))) | .card] | unique) as $offc
    | map(select((.step | IN("landed", "pushed")) and (.card | IN($offc[])) | not))
    | landed(.) as $done
    | ([.[] | select(.step == "landed" or (.step == "closed" and (.reason | IN($shut, $own, $eng) | not))) | .issue] | unique) as $landed
    | ($open[] | select((.parts // []) != [] and all(.parts[]; (.open | not) or (.number | IN($done[]))))
      | [.parts[] | select(.open and (.number | IN($done[]))) | .ref] as $l
      | "parts\t\(.number)\t\(.parts | map(.ref) | join(", "))\(if $l == [] then "" else "; landed, not closed yet: \($l | join(", "))" end)"),
      ([.[] | select(.step == "split" and (.split.filed | type) == "array" and .split.filed != [] and (.issue | IN($open[] | select((.parts // []) == []) | .number)))]
      | group_by(.issue)[] | last | select(all(.split.filed[]; IN($landed[]))) | "split\t\(.issue)\t\(.split.filed | map("#\(.)") | join(", "))"),
      ([.[] | select('"$TADONE"') | .card] | unique) as $lc
      | ([.[] | select(.step == "split" and (.split.cards | type) == "array" and .split.cards != [] and (.issue | IN($open[] | select((.parts // []) == []) | .number)))]
      | group_by(.issue)[] | last | select(all(.split.cards[]; . as $d | any($tac[0][]? | select(.id == $d) | .id, .card, (.was // [])[]; IN($lc[])))) | "split\t\(.issue)\t\(.split.cards | join(", "))")' \
    --slurpfile tac <([ ! -s "${TACARDS:-}" ] || jq -c '.cards | arrays' "$TACARDS" 2>/dev/null) <<<"$cs" 2>/dev/null)
}
# The issues given attached to <parent> as its GitHub sub-issues (its parts): GitHub takes each one's id, not its
# number. The id is read through graphql (privacy.test.sh's ghwrite refuses a REST call outside gh_write in lib/)
# as fullDatabaseId, a BigInt that GitHub sends as a string: databaseId is a 32-bit Int, and an id over 2147483647
# does not fit it. Prints why and fails at the first that cannot be attached; those before it stay attached.
attachparts() { # <parent> <issue>...
  local p=$1 n id out; shift
  for n; do
    id=$(gh api graphql -F owner='{owner}' -F repo='{repo}' -F number="$n" -f query='query($owner: String!, $repo: String!, $number: Int!) {
      repository(owner: $owner, name: $repo) { issue(number: $number) { fullDatabaseId } } }' 2>/dev/null \
      | jq -er '.data.repository.issue.fullDatabaseId | strings | select(test("^[0-9]+$"))' 2>/dev/null) || { echo "#$n could not be read"; return 1; }
    out=$(gh_write api "repos/{owner}/{repo}/issues/$p/sub_issues" -X POST -F "sub_issue_id=$id" 2>&1 >/dev/null) \
      || { echo "#$n could not be attached to #$p as its sub-issue: ${out:0:300}"; return 1; }
  done
}
