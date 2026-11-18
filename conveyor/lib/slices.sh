# SPDX-License-Identifier: Apache-2.0
# The rule Split large issues (the control record's rules.split: off, shadow or on; shadow by default). card() asks
# splitcheck() once, as the card starts and before its worktree is made, for an issue of its own (not a main-red fix
# card, issue 0, nor a branch). Its issue is left out when it is a follow-up (the pack's follow-up label: the slices of
# a split issue have it too), or when a split line of the card records or the retried lines already holds the same
# text of it (hash: the git hash of its title, a newline and its body): an issue is checked again only once it has
# been edited.
# Code first: the issue's size (SPLITSIZE: the items of its Done when section, the file paths and area labels it names,
# its characters) against the pack's split thresholds (split.doneWhen, split.files, split.areas, split.chars). An issue
# under all of them is kept with no model call. One at or over one of them is given to the judge (the Rules tab's
# Judge, the seat judgeseat() names), with no tools, once and SPLIT_TIMEOUT at most: its title and body, its Done-when
# items numbered D1, D2 and so on, and the files it names as they are on main (the first SPLIT_FILE characters of each,
# SPLIT_FILES files at most). The judge answers keep, or split into 2 or 3 slices (SPLITASK). An answer is used only
# when it holds to the rules (SPLITREAD): each slice has a title, Done-when items of its own and the parent's items it
# covers; every item of the parent is covered by exactly one slice; a slice depends only on slices before it. Any other
# answer, or a call that fails, keeps the issue whole, and the line says why.
# The card's split line records it: result kept or split, and split {mode (the rule: shadow or on), hash, verdict
# (under: under the thresholds; keep; split; invalid: an answer that broke the rules; failed: the call failed), why,
# size, slices ({title, doneWhen, covers, dependsOn}, each slice's number from 1), filed (the issues filed, On only),
# answer (the start of an answer that broke the rules)}, and model (the judge's) when the judge was asked.
# In shadow the card goes on and builds the issue whole, as with the rule off. On, with a split verdict, the slices are
# filed as follow-ups of the issue (splitfile()); the issue becomes their umbrella: it is held (`control hold`), gets a
# comment naming the slice that covers each of its Done-when items, and the card ends with a closed line whose
# followups are the slices (so a run limited by --only to the issue takes its slices too, ups() in DEPS); the issue
# stays open. umbrellas() closes it once each slice has a card that landed or closed it as done. A slice that cannot be filed withdraws the
# ones filed before it, and the issue is built whole.
SPLIT_TIMEOUT=300 SPLIT_FILE=6000 SPLIT_FILES=10
# The issue (its input, as gh issue view gives it) as the split check measures it. $area is the pack's area prefix.
# The Done when section is a heading or a line "Done when" (in bold or with a colon too) up to the next heading; its
# items are its bullets at the least indent (a nested bullet is part of its item). A file path is a word with a dot
# and an extension that starts with a letter, two characters or more before that dot (not e.g. or 4.7M); it can start
# with a dot, as a path in a hidden directory does (.claude/x.js).
SPLITSIZE='def dwsect: [splits("\r?\n")] as $l
    | ([range($l | length) | select($l[.] | test("^\\s*(#{1,6}\\s*)?(\\*\\*)?Done when(\\*\\*)?\\s*:?\\s*(\\*\\*)?\\s*:?\\s*$"; "i"))] | first) as $i
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
# The judge's prompt: SPLITASK, the issue, its Done-when items and the files it names, as main has them.
splitprompt() { # <issue json> <size json>
  local f n=0 t p
  p=$SPLITASK$'\n\n'$(jq -r --argjson s "$2" '"# The issue: #\(.number) \(.title // "")\n\n\(.body // "")\n\n# Its Done-when items\n"
    + ($s.doneWhen | to_entries | map("D\(.key + 1): \(.value)") | join("\n") | if . == "" then "(none)" else . end)' <<<"$1")
  p+=$'\n\n# The files it names, as they are on main'
  while IFS= read -r f && [ "$n" -lt "$SPLIT_FILES" ]; do
    t=$(git -C "$MAIN" show "refs/heads/$BRANCH:${f#./}" 2>/dev/null) || continue
    n=$((n + 1)); p+=$'\n\n## '"$f ($(wc -l <<<"$t" | tr -d ' ') lines)"$'\n'"${t:0:$SPLIT_FILE}"
  done < <(jq -r '.files[]' <<<"$2")
  [ "$n" != 0 ] || p+=$'\n\n(none of them is a file on main)'
  printf '%s' "$p"
}
splitcheck() { # <card> <issue>: 0 when the card goes on to build; 1 when the issue was split and the card has ended
  local c=${CARDCTL:-} rule issue h size t1 t2 t3 t4 p d rc s ans v model='' effort nums x split
  [ -n "$c" ] || c=$(ctl 2>/dev/null) || return 0
  rule=$(jq -r '.rules.split // "off"' <<<"$c" 2>/dev/null)
  [ "$rule" = shadow ] || [ "$rule" = on ] || return 0
  # An issue that cannot be read is built as it is, with no line: its card reads it again (card()).
  issue=$(gh issue view "$2" --json number,title,body,labels,milestone 2>/dev/null) && jq -e 'objects | .number' <<<"$issue" >/dev/null 2>&1 || return 0
  ! jq -e --arg fu "$FOLLOWUP" 'any(.labels[]?; .name == $fu)' <<<"$issue" >/dev/null 2>&1 || return 0
  h=$(jq -j '.title // "", "\n", .body // ""' <<<"$issue" | git hash-object --stdin) && [ -n "$h" ] || return 0
  [ "$({ recs; olds; } 2>/dev/null | grep -F "\"$h\"" | jq -Rn --argjson n "$2" --arg h "$h" \
    'any(inputs | fromjson? | objects; .step == "split" and .issue == $n and .split.hash == $h)' 2>/dev/null)" != true ] || return 0
  size=$(jq -c --arg area "$AREA" "$SPLITSIZE" <<<"$issue") && packget split.doneWhen t1 split.files t2 split.areas t3 split.chars t4 || return 0
  if jq -e --argjson t "[$t1,$t2,$t3,$t4]" '(.doneWhen | length) < $t[0] and (.files | length) < $t[1] and .areas < $t[2] and .chars < $t[3]' <<<"$size" >/dev/null; then
    v=$(jq -c '{verdict: "under", why: "under the pack'"'"'s split thresholds: \(.doneWhen | length) Done-when items, \(.files | length) files, \(.areas) areas, \(.chars) characters"}' <<<"$size")
  else
    s=$(seat judge "$c" 2>/dev/null) && jqget "$s" model model effort effort || { model='' effort=''; }
    p=$(splitprompt "$issue" "$size"); d=$(mktemp -d) || return 0
    if [ -n "${CONVEYOR_SPLIT_CMD:-}" ]; then
      (cd "$d" && exec timeout --kill-after=10 "$SPLIT_TIMEOUT" bash -c "$CONVEYOR_SPLIT_CMD" <<<"$p" > "$d/answer" 2>/dev/null 8>&- 9>&-); rc=$?; s=''
    else s=$(ASKSEAT=judge askmodel "$d" "$SPLIT_TIMEOUT" "${effort:-medium}" "$c" "$p"); rc=$?; fi
    ans=$(cat "$d/answer" 2>/dev/null); rm -rf "$d"
    if [ "$rc" != 0 ] || [ -n "$s" ]; then v=$(jq -cn --arg r "the judge call failed (${s:-exit $rc; 124 is the ${SPLIT_TIMEOUT}s timeout})" '{verdict: "failed", why: $r}')
    else v=$(jq -Rsc --argjson n "$(jq '.doneWhen | length' <<<"$size")" "$SPLITREAD" <<<"$ans" 2>/dev/null)
      [ -n "$v" ] || v=$(jq -cn --arg a "${ans:0:2000}" '{verdict: "invalid", why: "the answer held no JSON object", answer: $a}'); fi
  fi
  split=$(jq -c --arg m "$rule" --arg h "$h" --argjson s "$size" '{mode: $m, hash: $h, size: ($s | .doneWhen |= length | .files |= length)} + .' <<<"$v") || return 0
  # On, a split is filed; one that cannot be filed is recorded as a split not filed, and the issue is built whole.
  if [ "$rule" = on ] && [ "$(jq -r .verdict <<<"$split")" = split ]; then
    if nums=$(splitfile "$1" "$issue" "$(jq -c .slices <<<"$split")" "$c"); then split=$(jq -c --argjson f "$nums" '. + {filed: $f}' <<<"$split")
    else split=$(jq -c --arg r "$nums" '.why += "; the slices could not be filed, so the issue is built whole: \($r)"' <<<"$split"); fi
  fi
  record "$1" "$2" split "$(jq -r 'if .verdict == "split" then "split" else "kept" end' <<<"$split")" \
    "$(jq -c --arg m "$model" '{split: .} + (if $m != "" and .verdict != "under" then {model: $m} else {} end)' <<<"$split")"
  jq -e '.filed' <<<"$split" >/dev/null || return 0
  # The umbrella: held, told which slice covers each Done-when item, and its card closed; the issue stays open.
  x=$(locked control hold "$2" 2>&1 >/dev/null) || echo "conveyor: card $1: #$2 was split, and could not be held: ${x:0:300}" >&2
  x=$(jq -r --argjson s "$size" '"Conveyor split this issue under the rule Split large issues. Its follow-ups below build it, and this issue is not built itself. It stays open and held until each of them lands or is already done on main; then Conveyor closes it.\n\nEach Done-when item and the follow-up that covers it:\n"
    + ([.filed as $f | .slices | to_entries[] | .key as $k | .value.covers[] | {d: ., n: $f[$k]}] | sort_by(.d)
       | map("- D\(.d) (\($s.doneWhen[.d - 1] | .[0:160])): #\(.n)") | join("\n"))' <<<"$split")
  gh_write issue comment "$2" --body "$x" >/dev/null 2>&1 || echo "conveyor: card $1: #$2 was split; no comment could be added to it" >&2
  record "$1" "$2" closed ok "$(jq -c '{followups: .filed, reason: "split into \(.filed | map("#\(.)") | join(", ")) under the rule Split large issues: this issue is their umbrella, held, and Conveyor closes it when each of them lands or is already done on main"}' <<<"$split")"
  return 1
}
# The slices of a split, filed as follow-ups of <issue>: its priority, area and type labels and its milestone, the
# follow-up label, a body that opens "Follow-up of #<issue>", its Done-when items, the items of the parent it covers,
# and a `Depends on:` line naming the slices it depends on. They start where the parent is: held when the control
# record holds it, else queued. Prints their numbers as a JSON array; when one cannot be filed, prints why and fails,
# the ones filed before it withdrawn.
splitfile() { # <card> <issue json> <slices json> <the control record>
  local n k i out num nums=() more=() body held
  n=$(jq -r .number <<<"$2") && k=$(jq length <<<"$3") || { echo "the slices could not be read"; return 1; }
  mapfile -t more < <(jq -r --arg a "$AREA" --arg t "$TYPE" --argjson p "$PRIOS" '(.labels // [] | map(.name)
      | map(select(($a != "" and startswith($a)) or . == $t or IN($p[]))) | unique[] | "--label", .), (.milestone.title // empty | "--milestone", .)' <<<"$2")
  held=$(jq -r --argjson n "$n" '.held | index($n) != null' <<<"$4")
  for ((i = 0; i < k; i++)); do
    body=$(jq -r --argjson i "$i" --argjson k "$k" --arg c "$1" --arg area "$AREA" --argjson sl "$3" --argjson nums "$(jq -cn '$ARGS.positional | map(tonumber)' --args "${nums[@]}")" \
      '. as $iss | ('"$SPLITSIZE"' | .doneWhen) as $dw | $iss | .number as $n | $sl[$i] as $s
      | "Follow-up of #\($n): slice \($i + 1) of \($k). Conveyor card \($c) split #\($n) under the rule Split large issues. #\($n) stays open and held until each of its slices lands or is already done on main.\n\n"
        + "## The Done-when items of #\($n) this slice covers\n" + ($s.covers | map("- D\(.): \($dw[. - 1])") | join("\n"))
        + (if $s.dependsOn == [] then "" else "\n\nDepends on: " + ($s.dependsOn | map("#\($nums[. - 1])") | join(" ")) end)
        + "\n\n## Done when\n" + ($s.doneWhen | map("- " + .) | join("\n"))' <<<"$2") \
      && out=$(gh_write issue create --title "$(jq -r --argjson i "$i" '.[$i].title' <<<"$3")" --label "$FOLLOWUP" "${more[@]}" --body "$body" 2>&1) \
      && num=$(grep -oE '/issues/[0-9]+' <<<"$out" | tail -n 1) && num=${num##*/} && [ -n "$num" ] \
      || { splitwithdraw "$n" "${nums[@]}"; echo "slice $((i + 1)) was not filed: ${out:0:300}"; return 1; }
    nums+=("$num")
  done
  [ "$held" != true ] || out=$(locked control hold "${nums[@]}" 2>&1 >/dev/null) \
    || { splitwithdraw "$n" "${nums[@]}"; echo "the slices of a held issue could not be held: ${out:0:300}"; return 1; }
  jq -cn '$ARGS.positional | map(tonumber)' --args "${nums[@]}"
}
splitwithdraw() { # <issue> <slice>...
  local n=$1 x; shift
  for x; do gh_write issue close "$x" --reason "not planned" --comment "Conveyor: the split of #$n could not be filed whole, so this slice is withdrawn and #$n is built as one card." >/dev/null 2>&1; done
}
# At a turn of the loop, outside the lock: each open issue of the list that is the umbrella of a split (a split line
# with filed slices) whose slices each have a landed line, or a closed line (main already does it: ALREADY-DONE) that
# is not a shut one (SHUT: the owner closed it by hand), is closed, with a comment, and released from held.
umbrellas() { # <open issues, a json list>
  local n s x
  while read -r n s; do
    x=$(gh_write issue close "$n" --comment "Conveyor: the last follow-up of this issue is done ($s), so each of its Done-when items is built." 2>&1 >/dev/null) \
      || { echo "conveyor: #$n is an umbrella whose follow-ups have all landed or are already done on main, and it could not be closed (${x:0:300}); the next turn tries again" >&2; continue; }
    locked control release "$n" >/dev/null 2>&1 || :
  done < <(jq -rs --argjson open "$1" --arg shut "$SHUT" '([.[] | select(.step == "landed" or (.step == "closed" and .reason != $shut)) | .issue] | unique) as $landed
    | [.[] | select(.step == "split" and (.split.filed | type) == "array" and .split.filed != [] and (.issue | IN($open[].number)))]
    | group_by(.issue)[] | last | select(all(.split.filed[]; IN($landed[]))) | "\(.issue) \(.split.filed | map("#\(.)") | join(", "))"' < <(turncards) 2>/dev/null)
}
