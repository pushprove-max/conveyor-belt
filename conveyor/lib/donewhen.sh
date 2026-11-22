# SPDX-License-Identifier: Apache-2.0
# What a card's change is held to beside its tests: the product checks and the project's checks (checks(),
# treecheck()), its commit trailers (trailers()), the Done-when check of each session's reply (donewhen(), checked())
# and the review's findings across fix rounds (findings(), numbered(), rereview()). Sourced by lib/testrun.sh.
# The product checks, run by the loop beside the changed tests: a ratchet baseline raised in the same change
# as the code that needed the room, and a verification tuning schema added with no ring N-1 test
# (policy/api-conventions.md#data-access). Each takes <base> <head>: the base is the commit the card was built on
# (the worktree's HEAD), the head a commit made of the card's staged change on it, which no ref names. They are the
# pack's checks (the list, or its run when checks is an object), each a script path relative to main's checkout (or
# absolute): the loop's own copies, not the worktree's, so a card cannot change the check it is held to.
checks() { # <worktree>; prints the lines of every check that fails, and fails when one does
  local base head s out r rc=0 cs=()
  packget checks s && mapfile -t cs < <(jq -r 'if type == "object" then .run // [] else . end | .[]' <<<"$s") || { echo "the project pack's checks could not be read"; return 1; }
  base=$(git -C "$1" rev-parse HEAD 2>&1) && head=$(cd "$1" && git commit-tree "$(git write-tree)" -p "$base" -m "conveyor product checks" 2>&1) \
    || { echo "the card's change could not be made a commit for the product checks: ${head:-$base}"; return 1; }
  for s in "${cs[@]}"; do
    [[ $s == /* ]] || s=$MAIN/$s
    out=$(cd "$1" && bash "$s" "$base" "$head" 2>&1 < /dev/null 8>&-); r=$?
    [ $r = 0 ] || { rc=1; printf '%s (exit %s):\n%s\n' "${s##*/}" "$r" "$out"; }
  done
  return $rc
}
# The project's checks (the pack's test.checkCommand: a lint, shellcheck and the like), run in the worktree after each
# build, fix and rebase session (checked()) and at the start of a card's Test step (card()). Their result is kept for
# the tree they ran on, in <worktree>.checks/<key>.out and .rc, the key being HEAD and the tree of the worktree's
# tracked and untracked files (git add -A in a copy of its index, so the card's own index is not touched): a later
# call on the same tree prints the kept output and gives the kept result, and does not run the command again. Exit 0
# when they pass or the pack sets no command (nothing printed); 1 when they fail, with the command and its output
# (the first 20000 characters); 2 when the key cannot be read or the result cannot be kept, saying why.
treecheck() { # <worktree>
  local cc k h t r out d=$1.checks
  packget test.checkCommand cc || { echo "the project pack's test.checkCommand could not be read"; return 2; }
  [ -n "$cc" ] || return 0
  h=$(git -C "$1" rev-parse HEAD 2>/dev/null) || { echo "the worktree's commit could not be read for the checks"; return 2; }
  t=$(treeof "$1") || { echo "the worktree's tree could not be read for the checks"; return 2; }
  k=$d/$h-$t
  if [ -s "$k.rc" ] && [ -f "$k.out" ]; then r=$(<"$k.rc")
  else
    out=$(cd "$1" && bash -c "$cc" 2>&1 < /dev/null 8>&-); r=$?; [ $r = 0 ] || r=1
    mkdir -p "$d" && printf '%s\n' "$out" | head -c 20000 > "$k.out" && echo $r > "$k.rc" || { echo "the result of the checks could not be kept in $d"; return 2; }
  fi
  [ "$r" = 0 ] && return 0
  printf 'The checks failed (test.checkCommand: %s):\n%s\n' "$cc" "$(<"$k.out")"; return 1
}
# The kept results of the checks, put in a run's test log folder (CONVEYOR_TEST_LOG) as checks/<commit>-<tree>.out
# and .rc (tests()): a test command that runs the same checks can reuse the result for its tree, as this project's
# one-file runs do (.conveyor/test-changed.sh). A copy that fails leaves the run without them; it never fails.
checkskept() { [ ! -d "$1.checks" ] || cp -R "$1.checks" "$1.testlog/checks" 2>/dev/null || :; } # <worktree>


# Commit trailers. Conveyor writes every commit message, so a line a host's commit-msg hook requires (such as
# `Mutation-verified:`) is the card's to give: its sessions write such lines in <worktree>.trailers, and each kept line
# goes into the commit message after its `Closes` line. Kept: lines `<Token>: <text>` (a token of letters and hyphens),
# each under 300 characters, the first 10; never Co-Authored-By or a token the pack's commit.forbid names. The pack's
# commit.trailers names the ones a change owes: a rule's token when a path the change adds matches its when (an ERE).
# A kept `Rollout:` line is also a rollout action of the card (rollouts(), lib/prompts.sh; card() puts it on the landed line).
trailers() { # <worktree>: the kept lines, one a line
  local f
  packget commit.forbid f || return 1
  [ -e "$1.trailers" ] || return 0
  jq -Rrn --argjson f "$f" '([$f[], "Co-Authored-By"] | map(ascii_downcase)) as $no
    | [inputs | rtrimstr("\r") | select(test("^[A-Za-z][A-Za-z-]*: .*\\S") and length < 300) | select(split(":")[0] | ascii_downcase | IN($no[]) | not)]
    | .[:10][]' "$1.trailers"
}
# The section of the sessions' prompt that names the file and the pack's rules, each with its ask.
trailerbrief() { # <worktree>
  local r f
  packget commit.trailers r && packget commit.forbid f && f=$(jq -r 'map(", " + .) | join("")' <<<"$f") || return 1
  printf '%s' "# Commit trailers
Conveyor writes this card's commit message. A line the commit must carry goes in the file $1.trailers, one a line,
as \`<Token>: <text>\` with a token of letters and hyphens: each is added to the commit message after its \`Closes\`
line. Only lines of that shape are kept, the first 10, each under 300 characters; Co-Authored-By$f lines are dropped.
A step an operator must take, in order, for your change to work once deployed (a migration before the deploy, a new
environment value, a flag) goes there as one line \`Rollout: <the action> | <what fails without it> | <file:line>\`:
the card shows it apart from the review's findings."
  jq -r '.[] | "\n- When your change adds a file whose path matches the extended regular expression `\(.when)`: \(.ask) Write it as a `\(.token): <text>` line in that file."' <<<"$r"
}
# The brief's section that names the precheck command, with the engine's path (the brief of every card has it).
precheckbrief() {
  printf '# Precheck\n%s\n' "Before you end, run \`bash $HERE/conveyor.sh precheck <issue number> <file>\` in this worktree, the file holding your reply so far, and fix what it prints. Leave out the issue number and the file to skip the Done-when form."
}
# The pack's trailers the staged change owes and the card has not written: one {token, ask, paths} a line. The
# added paths are read unquoted and NUL-separated (-z), so a path git would quote, or one holding a newline, is matched
# whole; a when grep cannot read, or paths git cannot list, fails.
owing() { # <worktree>
  local r k m t rc
  packget commit.trailers r && t=$(trailers "$1") || return 1
  while IFS= read -r k; do
    m=$(set -o pipefail; git -C "$1" diff --cached --name-only --no-renames --diff-filter=A -z | grep -zE -- "$(jq -r .when <<<"$k")" | jq -Rsc 'split("\u0000") | map(select(. != ""))'); rc=$?
    [ $rc = 1 ] && continue
    [ $rc = 0 ] || return 1
    jq -c --argjson m "$m" --arg t "$t" 'select(.token | ascii_downcase | IN($t | split("\n")[] | split(":")[0] | ascii_downcase) | not)
      | {token, ask, paths: $m}' <<<"$k"
  done < <(jq -c '.[]' <<<"$r")
}
# What the review is shown beside the diff: the kept lines, nothing when there are none.
trailerview() { # <worktree>
  local t
  t=$(trailers "$1") || return 1
  [ -z "$t" ] || printf '\n\n# The commit trailers\nThe card wrote these lines in %s; they go into its commit message after its `Closes` line. Each must be true of the staged change:\n%s' "$1.trailers" "$t"
}

# The Done-when check: code, no model. The issue's `## Done when` section (to the next heading of level one or two)
# has a bullet per item; the session's reply ends with its own `## Done when` section, a line `D<n> met: <evidence>`
# or `D<n> not met: <why>` per item (card-core.md); a bracketed tag, as [uncertain: <why>] or [likely], may stand before
# the colon as well as after it, and the line, tag and all, is what the review sees. Each item needs its line; a met line needs evidence that is not
# empty, none, n/a or tbd. A file it names (a path with a folder and an extension, a bare file name with an
# extension, as missing.c or x.c, but not e.g. or i.e., or any name with a :line after it that has a folder, an
# extension or a capital first letter, as src/Makefile:1 or missing.c:1; a pytest ::case after a path is dropped) that
# is not in the worktree (a bare name may
# be at its root or in any folder; an absolute path, or one under ~, is not in it) does not fail the item: it is a note
# the review is shown beside the D<n> lines, as a reply often names a missing file on purpose (the owner, 2026-11-12).
# The items are the bullets at the section's least indent (a nested bullet is part of its
# item). Every TODO or [VERIFY]
# marker the staged change adds (more lines holding it added than removed, so a moved line is not added) must be
# named in the reply, on a line that names its file exactly. DONEWHEN reads the
# issue (its input), $r (the reply), $m (the added markers, [<file>, <marker>] pairs) and $wt; it prints nothing for
# an issue with no such section or no bullet in it, else {items, met (the items met so far), failed, paths ({n, p}:
# the files each met line names), lines (the reply's D<n> lines), detail (each item {n, text: the issue's bullet,
# said: the reply's D<n> line, null with none}, each cut to 500 characters)}.
DONEWHEN='def sect($t; $atend): [$t | splits("\r?\n")] as $l
    | [range($l | length) | select($l[.] | test("^#{1,2}\\s+Done when\\s*$"; "i"))] | (if $atend then last else first end) as $i
    | if $i == null then null else $l[($i + 1):] | (map(test("^#{1,2}\\s")) | index(true)) as $e | if $e == null then . else .[:$e] end end;
  def refs($s): [$s | scan("[^\\s`\"(),;<>]+") | sub("::.*$"; "") | capture("^(?<p>.*?)(?<l>:[0-9]+(-[0-9]+)?)?[.,:;]*$")
    | .p |= if startswith($wt + "/") then .[($wt | length) + 1:] else . end];
  def toks($s): [refs($s)[] | .p];
  (sect(.body // ""; false) // [] | map(capture("^(?<i>\\s*)[-*+]\\s+(?<t>\\S.*?)\\s*$")) | (map(.i | length) | min // 0) as $min
    | map(select((.i | length) == $min) | .t)) as $texts | ($texts | length) as $items
  | select($items > 0)
  | [sect($r; true) // [] | .[] | . as $x | capture("^\\s*(?:[-*+]\\s+)?`?D(?<n>[0-9]+)`?\\s+(?<k>met|not met)\\s*(?:\\[[^\\]]*\\]\\s*)?:\\s*(?<e>.*?)\\s*$"; "i")
      | .n |= tonumber | .k |= ascii_downcase | .line = $x] as $d
  | [range(1; $items + 1) as $n | ([$d[] | select(.n == $n)] | first) as $x
      | if $x == null then {n: $n, why: "D\($n): no `D\($n) met:` or `D\($n) not met:` line in the `## Done when` section that ends the reply"}
        elif $x.k == "not met" then {n: $n}
        elif ($x.e | gsub("^[\\s`*_]+|[\\s`*_.]+$"; "") | ascii_downcase | IN("", "none", "n/a", "tbd")) then {n: $n, why: "D\($n): met, with no evidence"}
        else {n: $n, met: true, paths: [refs($x.e)[] | select((.p | test("/") and test("\\.[A-Za-z][A-Za-z0-9]*$"))
            or (.p | test("^[A-Za-z0-9_][A-Za-z0-9_.-]*\\.[A-Za-z][A-Za-z0-9]*$") and (ascii_downcase | IN("e.g", "i.e") | not)) or (.l != null and (.p | test("/|\\.[A-Za-z]|^[A-Z]"))))
            | .p | select(test("://|^[$]") | not)] | unique} end] as $c
  | [$m[] | . as [$f, $k]
      | select(any($r | splits("\r?\n"); index($k) != null and IN(toks(.)[]; $f)) | not) | "\($k) added in \($f) is not named in the reply"] as $hid
  | {items: $items, met: [$c[] | select(.met) | .n], failed: ([$c[] | .why // empty] + $hid),
     paths: [$c[] | select(.met) | {n, p: .paths[]}], lines: [$d[] | select(.n <= $items) | .line],
     detail: [range(1; $items + 1) as $n | {n: $n, text: $texts[$n - 1][:500],
       said: ([$d[] | select(.n == $n) | .line | gsub("^\\s+|\\s+$"; "")[:500]] | first)}]}'
# The form of a reply written so far (a file holding its text), as `conveyor.sh precheck` asks it before a session
# ends: one line each of the issue's Done-when items the reply does not answer with a D<n> line and evidence, and
# each open-work marker the change (the index in use, addedmarks()) adds that the reply does not name. It keeps nothing.
dwform() { # <worktree> <issue json> <reply file>
  local m
  # No change: the reply is an ALREADY-DONE one line, and the engine checks no form (donewhen()).
  git -C "$1" diff --cached --quiet 2>/dev/null && return 0
  m=$(addedmarks "$1") || return 1
  jq -r --rawfile r "$3" --argjson m "$m" --arg wt "$1" "$DONEWHEN | .failed[]" <<<"$2"
}
# The open-work markers the staged change (the index in use) adds, as [<file>, <marker>] pairs in a JSON list.
addedmarks() { # <worktree>
  local k p t v
  # A marker counts as added only when the whole change has more added lines holding it than removed ones: a line
  # moved from one file to another adds none. t and v are 1 when TODO and [VERIFY] are added, else 0.
  read -r t v < <(git -C "$1" diff --cached --no-renames --no-color -U0 | awk '/^diff --git / {h = 0; next} /^@@/ {h = 1; next}
    h && /^[+-]/ {d = substr($0, 1, 1) == "+" ? 1 : -1; if (index($0, "TODO")) a += d; if (index($0, "[VERIFY]")) b += d}
    END {print (a > 0) + 0, (b > 0) + 0}')
  # File by file, the names read NUL-separated (-z) and passed literally, so a name git would quote in a diff header is
  # read whole; the added lines are the + lines after the first hunk header.
  git -C "$1" diff --cached --name-only --no-renames --diff-filter=d -z | while IFS= read -r -d '' p; do
      k=$(git -C "$1" diff --cached --no-renames --no-color -U0 -- ":(literal)$p" | awk '/^@@/ {h = 1; next} h && /^\+/')
      [[ $t = 0 || $k != *TODO* ]] || printf '%s\0TODO\0' "$p"; [[ $v = 0 || $k != *'[VERIFY]'* ]] || printf '%s\0[VERIFY]\0' "$p"
    done | jq -Rsc 'split("\u0000") | .[:-1] | [range(0; length; 2) as $i | .[$i:$i + 2]]'
}
# The check of the last session's reply (its stream in <worktree>.out) against the staged change: prints
# {items, met, failed} (and notes, the files named that are not there, when there is one), and detail (DONEWHEN's),
# nothing when it is skipped
# (no such section, or no change: an ALREADY-DONE goes its own way), and keeps the reply's D<n> lines and those notes
# in <worktree>.donewhen for the review.
donewhen() { # <worktree> <issue json>
  local m k n p miss='[]'
  rm -f "$1.donewhen"
  git -C "$1" add -A 2>/dev/null && ! git -C "$1" diff --cached --quiet 2>/dev/null || return 0
  m=$(addedmarks "$1") || return 1
  # The issue and the reply come on stdin and in a file: either can be more than one argument can hold.
  k=$(jq -c --rawfile r <(jq -Rrjn '[inputs | fromjson? // empty | objects | select(.type == "result") | .result | strings] | last // ""' "$1.out" 2>/dev/null) \
    --argjson m "$m" --arg wt "$1" "$DONEWHEN" <<<"$2") || return 1
  [ -n "$k" ] || return 0
  while IFS=$'\t' read -r n p; do
    [[ /$p/ != */../* ]] && { [ -e "$1/$p" ] || { [[ $p != */* ]] && git -C "$1" ls-files | awk -F/ -v p="$p" '$NF == p {f = 1} END {exit !f}'; }; } || miss=$(jq -c --argjson n "$n" --arg p "$p" '. + [{n: $n, p: $p}]' <<<"$miss")
  done < <(jq -r '.paths[] | "\(.n)\t\(.p)"' <<<"$k")
  miss=$(jq -c 'unique_by([.n, .p])[] | "D\(.n): names \(.p), which is not in this worktree"' <<<"$miss" | jq -sc .)
  { jq -r '.lines[]' <<<"$k"; jq -r '.[] | "Note: " + .' <<<"$miss"; } > "$1.donewhen"
  jq -c --argjson x "$miss" '{items, met: (.met | length), failed} + (if $x == [] then {} else {notes: $x} end) + {detail}' <<<"$k"
}
# `conveyor.sh history donewhen <card>`: the card's last Done-when check, item by item, which the snapshot leaves out
# (the Board asks for it when a card's Done-when line is opened): {card, items: [{n, text, builder, reviewer}]}, from
# the card's last line with doneWhenItems and the last review after it. builder is the session's D<n> line; reviewer
# is "holds" for a D<n> the review said holds (doneWhenHolds), else its findings that name D<n> (from its reason, cut to
# 1500 characters, and a NO-GO's tail, which keeps its last lines whole), else null. items is []
# when no line of the card has the check.
dwdetail() { # <card>
  { olds; recs; } 2>/dev/null | jq -cRn --arg c "$1" '[inputs | fromjson? | objects | select(.card == $c)] as $l
    | ([$l | to_entries[] | select(.value.doneWhenItems | type == "array")] | last) as $b
    | ([$l[(($b.key // -1) + 1):][] | select(.step == "review")] | last) as $r
    | [$r.tail | strings | splits("\n")] as $t
    | ([$r.reason | strings | splits("\n") | . as $x | select(any($t[]; startswith($x)) | not)] + $t) as $f
    | {card: $c, items: [($b.value.doneWhenItems // [])[] | objects | .n as $n | {n, text, builder: .said,
        reviewer: (if $r == null then null elif any($r.doneWhenHolds[]?; . == $n) then "holds"
          else [$f[] | select(test("\\bD\($n)\\b"))] | if . == [] then null else join("\n") end end)}]}'
}
# A card's excerpts, which the snapshot leaves out: the lines each of its reviews' findings cites, as its review lines
# keep them (excerpts(), lib/review.sh), oldest review first, each with the time of the review line that kept it (the
# time the Board's review step has, at), so a review shows its own lines and not a later one's at the same place:
# {card, excerpts: [{review, at, side, from, lines}]}. The Board reads it when a finding's place is opened (history excerpts).
exdetail() { # <card>
  { olds; recs; } 2>/dev/null | jq -cRn --arg c "$1" '{card: $c, excerpts: [inputs | fromjson? | objects
    | select(.card == $c and .step == "review") | .time as $t | .excerpts | arrays[] | objects | {review: $t} + .]}'
}
# The reply's D<n> lines as donewhen() kept them in <worktree>.donewhen, each with its state (met or not met), cut to
# 300 characters: a JSON array, for the session's line (doneLines; the pull request of Land as pr lists them). With no
# such file (the issue has no Done-when section) jq 1.8 still prints the slurped value, [], and then fails, so the file
# is read on jq's input and jq's output is kept only when it worked: printed with the fallback, it was two arrays, no
# JSON text for --argjson, dwfields() gave nothing, and record() wrote the line without the session's fields (its tokens,
# stats and Done-when check).
donelines() { local d; d=$(jq -Rsc '[splits("\n") | select(. != "" and (startswith("Note: ") | not)) | .[0:300]]' 2>/dev/null < "$1.donewhen") && printf '%s\n' "$d" || echo '[]'; }
# A session's fields for its line in checked(), with the Done-when check put on them by <jq filter> ($k the check
# donewhen() printed, less its detail; $i that detail, doneWhenItems, which the snapshot leaves out: the Board reads it
# on demand, history donewhen; $d the reply's D<n> lines); when they cannot be put together, the log names the card
# and the line, and the line is written without them.
dwfields() { # <card> <worktree> <step> <the Done-when check, or ""> <jq filter> [jq options]... (the session's fields on stdin)
  local c=$1 wt=$2 s=$3 k=$4 f=$5 x; shift 5
  x=$(jq -c --argjson k "$(jq -c 'if . == null then . else del(.detail) end' <<<"${k:-null}")" --argjson i "$(jq -c '.detail?' <<<"${k:-null}")" \
    --argjson d "$(donelines "$wt")" "$@" "$f") \
    || { echo "conveyor: card $c: the $s session's fields (its tokens, stats and Done-when check) could not be put on its $s line; the line is written without them" >&2; return 0; }
  printf '%s\n' "$x"
}
# The tree of a worktree's files as they are, staged, unstaged and untracked (not ignored), written through a copy of
# its index so its own index is left as it is: the key of treecheck()'s kept result and the tree asks() compares.
# The copy keeps the index's time (cp -p): git reads a file staged in the second the index was written as possibly
# changed only by that time, so a plain copy (a new time) let a same-size rewrite in that second count as unchanged.
# Fails, printing nothing, when it cannot be written.
treeof() { # <worktree>
  local i t r
  i=$(mktemp) || return 1
  cp -p "$(git -C "$1" rev-parse --path-format=absolute --git-path index)" "$i" 2>/dev/null || rm -f "$i"
  t=$(GIT_INDEX_FILE=$i git -C "$1" add -A 2>/dev/null && GIT_INDEX_FILE=$i git -C "$1" write-tree 2>/dev/null); r=$?
  rm -f "$i"; [ $r = 0 ] && [ -n "$t" ] && printf '%s\n' "$t"
}
# The question a session's reply ends with, when the session changed nothing: its worktree's tree is the one session()
# kept before it (<worktree>.before), so a fix whose earlier change is still staged counts too. The question is the
# reply's last paragraph, on one line, cut to 1000 characters, when it ends with a question mark (quote, bracket or
# emphasis marks after it aside). The reply is the last text of the session's stream: a Claude result, a Codex
# agent_message or an OpenCode text part. Fails when the session made a change, its tree before is not known, or the
# reply does not end with a question.
asks() { # <worktree>
  local q b
  b=$(cat "$1.before" 2>/dev/null) && [ -n "$b" ] && [ "$(treeof "$1" 2>/dev/null)" = "$b" ] || return 1
  q=$(jq -Rrjn '[inputs | fromjson? // empty | objects | if .type == "result" then .result
      elif .type == "item.completed" and .item.type? == "agent_message" then .item.text elif .type == "text" then .part.text? else empty end
      | strings | select(test("\\S"))] | last // ""' "$1.out" 2>/dev/null \
    | awk 'NF == 0 { b = 1; next } { $1 = $1; p = (b || p == "") ? $0 : p " " $0; b = 0 } END { print p }')
  [[ $q =~ \?[\"\'\)\*_\`]*$ ]] || return 1
  printf '%s\n' "${q:0:1000}"
}
# A build, fix or rebase session's line, with the Done-when check of its reply on it (doneWhen, and the reply's D<n>
# lines: doneLines). A session that changed nothing and asks the owner a question (asks()) blocks the card with that
# question, before the check; so does each fix session below that changed nothing and asks one. A failed check is not a block: one fix session is told the failed items, as a NO-GO's findings
# are, and the check runs again on its reply, its line carrying that result; a second failure blocks the card with the items listed.
# Then the project's checks (treecheck()), before any review or test: a failure goes to one fix session told their
# output, and they run again on its change; a second failure blocks the card with that output. Fails when the card blocked.
checked() { # <card> <issue> <worktree> <issue json> <the sessions' prompt> <step> <the session's fields>
  dwchecked "$@" || return 1
  local out t r
  out=$(treecheck "$3"); r=$?
  [ $r != 2 ] || { block "$1" "$2" "$3" "the engine could not run the project's checks: $out"; return 1; }
  [ $r != 0 ] || return 0
  began "$1" "$2" fix
  t=$(session "$3" "$5"$'\n\n'"$CHECKFIX"$'\n'"$out" fix) || { block "$1" "$2" "$3" "fix: $t"; return 1; }
  record "$1" "$2" fix ok "$(jq -c --arg r "the project's checks failed (test.checkCommand)" '. + {reason: $r}' <<<"$t")"
  [ "$2" = 0 ] || ! t=$(asks "$3") || { block "$1" "$2" "$3" "fix: the session changed nothing and asks the owner: $t"; return 1; }
  out=$(treecheck "$3"); r=$?
  [ $r != 2 ] || { block "$1" "$2" "$3" "the engine could not run the project's checks: $out"; return 1; }
  [ $r = 0 ] || { block "$1" "$2" "$3" "the project's checks failed again after their one fix session; nothing landed."$'\n'"$out"; return 1; }
}
dwchecked() { # <card> <issue> <worktree> <issue json> <the sessions' prompt> <step> <the session's fields>: the Done-when part of checked()
  local k t f
  k=$(donewhen "$3" "$4") || { block "$1" "$2" "$3" "the engine could not run the Done-when check"; return 1; }
  record "$1" "$2" "$6" ok "$(dwfields "$1" "$3" "$6" "$k" 'if $k == null then . else . + {doneWhen: $k, doneWhenItems: $i, doneLines: $d} end' <<<"$7")"
  # A session that changed nothing and ends by asking the owner something (asks()) goes to the owner, with its
  # question as the reason: no Done-when fix, check or review answers it (#466). Not a main-red fix card (issue 0):
  # with no change, it runs main's failing cases again (nochange()), which no owner's answer replaces.
  [ "$2" = 0 ] || ! t=$(asks "$3") || { block "$1" "$2" "$3" "$6: the session changed nothing and asks the owner: $t"; return 1; }
  [ -n "$k" ] && [ "$(jq '.failed | length' <<<"$k")" != 0 ] || return 0
  f=$(jq -r '.failed | join("; ")' <<<"$k")
  began "$1" "$2" fix
  t=$(session "$3" "$5"$'\n\n'"$DWFIX"$'\n'"$(jq -r '.failed[] | "- " + .' <<<"$k")" fix) || { block "$1" "$2" "$3" "fix: $t"; return 1; }
  k=$(donewhen "$3" "$4") || { block "$1" "$2" "$3" "the engine could not run the Done-when check"; return 1; }
  record "$1" "$2" fix ok "$(dwfields "$1" "$3" fix "$k" '. + {reason: $r} + (if $k == null then {} else {doneWhen: $k, doneWhenItems: $i, doneLines: $d} end)' \
    --arg r "the Done-when check failed: $f" <<<"$t")"
  [ "$2" = 0 ] || ! t=$(asks "$3") || { block "$1" "$2" "$3" "fix: the session changed nothing and asks the owner: $t"; return 1; }
  [ -z "$k" ] || [ "$(jq '.failed | length' <<<"$k")" = 0 ] \
    || { block "$1" "$2" "$3" "the Done-when check failed again after its one fix session: $(jq -r '.failed | join("; ")' <<<"$k")"; return 1; }
}

# The findings of a review at each level, as its record line holds them: counted over the whole review, of which
# the line keeps only the first 1500 characters. A finding is any line followups() would file, and one with no
# [P0] to [P3] mark counts as P1, the level it is filed at. An accepted P3 listed only (a MINOR line, minor()) counts
# as the P3 it is.
counts() { # <review file>
  sed -E 's/^MINOR:[[:space:]]*//' "$1" | grep -Ev "$NOTFINDING" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//' | awk '!seen[$0]++' | jq -cRn '[inputs | select(test("[^[:space:]]")) | (capture("\\[(?<p>P[0-3])\\]").p // "P1")] as $p
    | {P0: 0, P1: 0, P2: 0, P3: 0} | with_entries(.key as $k | .value = ($p | map(select(. == $k)) | length))'
}
# A finding that comes back after its fix. Each fix round after a NO-GO keeps, in the folder <worktree>.rounds, the
# findings it was told to fix (findings.jsonl, rounded()) and the diff it made (<round>.diff); a card that blocks
# keeps that folder, and the card that retries from its patch starts from it. Each finding has an id, E1, E2 and so
# on, given when it is first recorded and kept by every later finding that is the same one (numbered()). A finding's
# key is the first file:line it names (at) and its first six words (words), lower case, letters and digits only,
# leaving out its level mark, an id mark ([E3]), that file:line and any proof after `Proof:`. named is the id its
# id mark names, else null.
findings() { # <review file>: one JSON line per finding, {line, level, at, named, words, key}
  grep -Ev "$NOTFINDING" "$1" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//' | awk 'NF && !seen[$0]++' | jq -cR '. as $f
    | ([scan("[A-Za-z0-9_./-]+:[0-9]+")] | first // "") as $w
    | (gsub("\\[P[0-3]\\]|\\[E[0-9]+\\]"; "") | if $w == "" then . else index($w) as $i | .[:$i] + .[$i + ($w | length):] end
         | split("Proof:")[0] | ascii_downcase | [scan("[a-z0-9]+")] | .[:6] | join(" ")) as $k
    | {line: $f, level: (capture("\\[(?<p>P[0-3])\\]").p // "P1"), at: $w, named: (capture("\\[(?<e>E[0-9]+)\\]").e // null), words: $k, key: ($w + " " + $k)}'
}
# The findings of the review beside the worktree, each with its id (findings() lines with id and seen). A finding
# keeps the id of an earlier one (seen true) when its id mark names a recorded id, or when its key is the moved key
# (mkey, rounded()) of the latest record of that id: its location where the diff of that fix round put it. One whose
# location needs review has no moved key, so only its id joins it. Each other finding is new, numbered on from the
# highest id recorded on the card.
numbered() { # <worktree>
  findings "$1.review" | jq -sc --slurpfile h <(cat "$1.rounds/findings.jsonl" 2>/dev/null) '
    [$h | group_by(.id)[] | last] as $l | ([$h[].id | ltrimstr("E") | tonumber] | max // 0) as $n
    | reduce .[] as $f ({n: $n, out: []};
        (if $f.named != null and any($h[]; .id == $f.named) then $f.named else [$l[] | select(.mkey == $f.key) | .id] | first end) as $id
        | if $id != null then .out += [$f + {id: $id, seen: true}] else .n += 1 | .out += [$f + {id: "E\(.n)", seen: false}] end)
    | .out[]'
}
# Where a diff puts line <n> of the file <p> (a path, or its end after a /, as a finding names it): "<path>:<line>",
# the same file:line when the diff does not change that file or the lines above it, the new path when it renames the
# file, or null when it removes or replaces that line or deletes the file. The file is the path <p> names exactly, in
# the worktree's files ($ls) or the diff; else the one file whose path ends in "/<p>"; when more than one does, which
# file it names is not known, so null too.
# shellcheck disable=SC2016 # jq's $ names, not the shell's
MOVEJQ='def files: reduce (split("\n")[]) as $l ([];
    if $l | startswith("diff --git ") then . + [{old: null, new: null, hunks: []}]
    elif length == 0 then .
    elif .[-1].hunks == [] and ($l | startswith("--- ")) then .[-1].old = ($l[4:] | if . == "/dev/null" then null else ltrimstr("a/") end)
    elif .[-1].hunks == [] and ($l | startswith("+++ ")) then .[-1].new = ($l[4:] | if . == "/dev/null" then null else ltrimstr("b/") end)
    elif .[-1].hunks == [] and ($l | startswith("rename from ")) then .[-1].old = $l[12:]
    elif .[-1].hunks == [] and ($l | startswith("rename to ")) then .[-1].new = $l[10:]
    elif $l | test("^@@ -[0-9]+(,[0-9]+)? \\+[0-9]+(,[0-9]+)? @@") then ($l | capture("^@@ -(?<a>[0-9]+)(,(?<b>[0-9]+))? \\+(?<c>[0-9]+)(,(?<d>[0-9]+))? @@")) as $m
      | .[-1].hunks += [{a: ($m.a | tonumber), b: ($m.b // "1" | tonumber), c: ($m.c | tonumber), d: ($m.d // "1" | tonumber), m: []}]
    elif .[-1].hunks != [] and ($l | test("^[ +-]")) then .[-1].hunks[-1].m += [$l[:1]]
    else . end);
  def moveto($fs; $ls; $p; $n): ($p | ltrimstr("./")) as $q
    | ($ls + [$fs[].old | strings] | unique) as $all
    | (if any($all[]; . == $q) then [$q] else [$all[] | select(endswith("/" + $q))] end) as $c
    | ([$fs[] | select(.old == $c[0])] | first) as $f
    | if ($c | length) > 1 then null elif $f == null then "\($p):\($n)" elif $f.new == null then null
      else reduce $f.hunks[] as $h ({off: 0, at: null, gone: false};
          if .at != null or .gone then .
          elif ($h.b > 0 and $n < $h.a) or ($h.b == 0 and $n <= $h.a) then .at = $n + .off
          elif $h.b == 0 or $n >= $h.a + $h.b then .off += $h.d - $h.b
          else reduce $h.m[] as $k (. + {o: $h.a, w: $h.c};
              if .at != null or .gone then .
              elif $k == "+" then .w += 1
              elif .o == $n then if $k == " " then .at = .w else .gone = true end
              elif $k == "-" then .o += 1
              else .o += 1 | .w += 1 end) end)
        | if .gone then null else "\(if $f.new == $f.old then $p else $f.new end):\(.at // ($n + .off))" end end;'
# Records the findings fix round <round> was told to fix, with the ids numbered() gave them, in findings.jsonl: each
# {round, id, line, level, at, words, key} with, after the round's diff (<round>.diff), moved (the file:line its
# location is at now, moveto()) and mkey (moved and its words), or location "needs review" when the diff removed or
# replaced its line: such a finding keeps its first line and proof, and is joined to a later one by its id alone. A
# finding with no location keeps its key as mkey. A finding recorded before carries first, its first record's round,
# location and line (with its proof). Each earlier finding this round was not told (one a review said holds) is
# followed through the round's diff too, in a record {round, id, words, tracked: true} with moved and mkey, or location
# "needs review": its key keeps to its code, so a later finding at the line that took its place is not joined to it.
rounded() { # <worktree> <round> <numbered() lines>
  [ -n "$3" ] || return 0
  jq -cs --argjson r "$2" --rawfile d "$1.rounds/$2.diff" --rawfile ls <(git -C "$1" ls-files) --slurpfile h <(cat "$1.rounds/findings.jsonl" 2>/dev/null) "$MOVEJQ"'
    ($d | files) as $fs | ($ls | split("\n") | map(select(. != ""))) as $l | map(.id) as $ids
    | def follow($at; $w): ($at | capture("^(?<p>.*):(?<n>[0-9]+)$")) as $a | moveto($fs; $l; $a.p; ($a.n | tonumber))
        | if . == null then {location: "needs review"} else {moved: ., mkey: (. + " " + $w)} end;
    (.[] | . as $f | ([$h[] | select(.id == $f.id)] | first) as $o
      | del(.named, .seen) + {round: $r}
      + (if $f.at == "" then {mkey: $f.key} else follow($f.at; $f.words) end)
      + (if $o == null then {} else {first: ($o | {round, at, line})} end)),
    ($h | group_by(.id)[] | last | select(.moved != null and (.id | IN($ids[]) | not))
      | {round: $r, id, words, tracked: true} + follow(.moved; .words))' <<<"$3" >> "$1.rounds/findings.jsonl"
}
# The review beside the worktree as its fix session is told it (FIX): every line but the DECLINED, MINOR and ROLLOUT
# ones (a rollout action is no defect, rollouts()), each finding led by its id (<numbered() lines>).
fixlines() { # <worktree> <numbered() lines>
  grep -Ev "^(DECLINED|MINOR):|^ROLLOUT: $ROLLOUT" "$1.review" | jq -Rr --slurpfile n <(printf '%s\n' "$2") '($n | map({key: .line, value: .id}) | from_entries) as $m
    | (sub("^\\s+"; "") | sub("\\s+$"; "")) as $t | if $t != "" and $m[$t] then "\($m[$t]) \(.)" else . end'
}
# The findings of the review beside the worktree that a fix round was already told to fix (numbered(): the same id),
# one JSON line each: {id, line, level, rounds: how many fix rounds were told it, before: the finding as the last of
# them was told it, diff: the file of that round's diff}.
repeats() { # <worktree>
  [ -s "$1.rounds/findings.jsonl" ] || return 0
  numbered "$1" | jq -c --slurpfile h "$1.rounds/findings.jsonl" --arg d "$1.rounds" 'select(.seen) | . as $f | [$h[] | select(.id == $f.id and (.tracked | not))]
    | select(length > 0) | {id: $f.id, line: $f.line, level: $f.level, rounds: (map(.round) | unique | length), before: last.line, diff: "\($d)/\(last.round).diff"}'
}
# The review beside the worktree's answers on the findings fix rounds were told, for its record line, one JSON array:
# {id, answer: its finding again (numbered()), or "holds" for its `EARLIER: E<n> holds` line, first: the round, location
# and line (with its proof) the finding was first recorded with}. Lines are cut at 500 characters.
answers() { # <worktree>
  [ -s "$1.rounds/findings.jsonl" ] || { echo '[]'; return 0; }
  { numbered "$1" | jq -c 'select(.seen) | {id, answer: .line}'
    grep -E '^EARLIER: E[0-9]+ holds[[:space:]]*$' "$1.review" | jq -cR '{id: capture("(?<e>E[0-9]+)").e, answer: "holds"}'; } \
    | jq -sc --slurpfile h "$1.rounds/findings.jsonl" 'map(. as $a | ([$h[] | select(.id == $a.id and (.tracked | not))] | first) as $o
        | select($o != null) | {id, answer: .answer[:500], first: ($o | {round, at, line: .line[:500]})})'
}
# What the fix session after a review that repeats a finding is told, after the review: each finding that came back,
# the finding as the earlier review gave it (its proof with it) and the diff of the fix round after that review.
again() { # <repeats() lines>
  local l d
  printf '%s\n' '# These findings came back after a fix round for them' \
    'The review found each of them again after an earlier fix session changed the code for it: that fix did not hold. Do not make the same change again: read in the proof why it did not hold, and take another approach.'
  while IFS= read -r l; do
    d=$(jq -r .diff <<<"$l")
    jq -r '"\n## \(.line)\nIt came back after \(.rounds) fix round\(if .rounds == 1 then "" else "s" end) for it. The earlier review said:\n\(.before)\nThe diff of the fix round after that review (the file \(.diff)):"' <<<"$l"
    printf '```diff\n%s\n```\n' "$(head -c 20000 "$d" 2>/dev/null)"
    [ "$(wc -c < "$d" 2>/dev/null || echo 0)" -le 20000 ] || echo "That diff is cut short here: read all of it in its file."
  done <<<"$1"
}
# Does the review after fix round <round> review the fix alone? Yes when the fix's diff touches no more than the
# pack's review.rereviewWhole percent of the staged change's lines (its added and removed lines, as git counts them; a
# binary file counts none). It fails, and the whole change is reviewed, when the fix touches more, when the staged
# change has no such line, or when a count cannot be read.
fixonly() { # <worktree> <round>
  local w f='' a d=$1.rounds/$2.diff
  packget review.rereviewWhole w && [[ $w =~ ^[0-9]+$ ]] && [ -f "$d" ] || return 1
  [ ! -s "$d" ] || f=$(git -C "$1" apply --numstat "$d") || return 1
  a=$(git -C "$1" diff --cached --numstat) || return 1
  f=$(awk '{n += $1 + $2} END {print n + 0}' <<<"$f"); a=$(awk '{n += $1 + $2} END {print n + 0}' <<<"$a")
  [ "$a" -gt 0 ] && [ $((f * 100)) -le $((a * w)) ]
}
# What the review after fix round <round> is told, in its brief (REREVIEW): what else it may raise (the whole change,
# or with fix as fourth argument the fix's lines and their callers alone), the findings that round was told to fix,
# each led by its id (rounded()) and followed by where the fix moved its location or that its location needs review,
# the file of its diff, and the findings declined on this card so far, each with its reason.
rereview() { # <card> <worktree> <round> [fix]
  local dec t=$REREVIEWALL
  [ "${4:-}" != fix ] || t=$REREVIEWFIX
  printf '%s\n%s\n\n## The findings the fix was told to fix\n' "$REREVIEW" "$t"
  jq -rs --argjson r "$3" 'map(select(.round == $r and (.tracked | not)))[] | "\(.id) \(.line)"
    + if .location == "needs review" then "\n  Its location needs review: the fix removed or replaced the lines it named. Find where the defect is now, if it is anywhere."
      elif .moved != null and .moved != .at then "\n  The fix moved its location to \(.moved)." else "" end' "$2.rounds/findings.jsonl"
  printf '\n## The diff of the fix\nThe file %s\n' "$2.rounds/$3.diff"
  dec=$(stdb ask lines declined 2>/dev/null | jq -rR --arg c "$1" 'fromjson? | objects | select(.card == $c) | "- \(.finding) (declined: \(.why))"' 2>/dev/null | awk '!seen[$0]++')
  printf '\n## The findings declined on this card\n%s\n' "${dec:-None.}"
}
