# SPDX-License-Identifier: Apache-2.0
# Same-file cards. Two cards in flight that changed the same file found out only at landing,
# where the second one's change no longer applied. Cards review in parallel; each claims the files its staged change
# names after its review, before it lands, in <worktree>.claim: {pid: the card's process, paths, held, passed: an ordered card went
# past it since, was: passed as it stood when this claim was granted}, the change itself beside it (<worktree>.cpatch).
# Two cards that share a file overlap only when their changes do not apply together (together()): a card whose change
# merges three-way with no conflict onto main with the other's already applied shares no file with it in what follows,
# so same-file changes to different parts of a file neither wait for nor go past each other, as cards on different
# files. Documentation files (*.md, README.md among them) are never shared: a claim names none, so they make no card
# wait (the owner, 2026-11-13: nearly every card changes README.md); two cards whose edits to one conflict meet that at
# landing, where the later one's rebuild session resolves it, its review and test pass standing when that session left
# its change outside documentation as it was (settle(), card()). A claim goes with the
# worktree, and counts only while its card's process is alive and the card is on the belt: picked (its picked line is
# in the card records) and not landed, closed or blocked. A card that blocked, or whose lines `retry` moved out, is
# not running, and a card that waited on it would hold its slot for good. A card holds its files (held) from a claim it did not
# wait at until its next claim, so a card keeps them from its landing step through its checks, tests and landing,
# unless it gives way (giveway()) for a fit onto main, a review, a fix or a test fix before it can land; one that gave
# way runs its checks and tests before it claims again (card()), so it holds its files only to land. A card
# waits while another card holds one of its files, older or younger, or while a card that goes before it waits for one
# of them. A card whose issue is in the control record's order list (an ordered card) does not wait for a holder that
# is not ordered: it claims the files and goes on, and that card waits for it at its own next claim (before it
# lands); two ordered cards never go past each other. A ready card lands first (the owner, 2026-11-18): a card whose
# tests passed on the change it holds on main (readysince(), its change fitting main as it is now: ready()) does not
# wait for a holder of the same rank in order whose tests have not passed, or passed later: it claims the files and
# goes on, and that card waits for it at its own next claim, then is fitted onto main with its change (settle()),
# marked fit, so it is reviewed again only when the fit changed its change. Among waiting cards with no holder, an
# ordered card goes before any other, the earlier in order first, then a card whose tests passed before one whose
# tests have not, the one whose tests passed first (since) first, and otherwise the older pick (its picked line comes
# first) goes first. This prints {on: that card, paths: the files they share}, naming of several such cards the one
# that goes first (an ordered one before any other). A card that is ready (ready()) does not wait for a waiting card
# that goes before it only by those tests or its pick and is not ready: that card could not land yet anyway. So of the
# cards whose changes do not apply together, only one at a time is past its claim on a file, even when a fix adds a file
# another card holds, except while an ordered or a ready card has gone past a card that is not; landing stays one at a time under
# the lock. A waiting card holds nothing, so two cards never wait on
# each other. A card that gave way (giveway(): away) holds nothing and waits for no card until it claims the files
# again: a card that is ready (ready()) goes past it, and one that is not waits for it as for a holder until it is
# back at its claim (back). Back there and waiting, it waits too for the cards it gave way to (for) that are ready
# and have not yet claimed the files, and stays away. Its claims keep its count of give-ways (gave). The card that
# claims the files of one that gave way is named on it (to: its issue), for the Board and its live record (watch()).
claim() { # <card> <worktree> <the card's pid>; under the lock
  local mine others o c w ord passed fit gave away for='[]' apart='[]' notready=0 unready='[]' stk t ms=null rdy='{}'
  ord=$(ctl 2>/dev/null) && ord=$(jq -c .order <<<"$ord") || ord='[]'
  away=$(jq -c 'select(.away == true) | {away, for: (.for // [] | arrays), to: (.to // null), fixing: (.fixing == true)}' "$2.claim" 2>/dev/null) && [ -n "$away" ] || away='{"for": []}'
  # This runs every turn of a wait (settle()), so it starts no program whose answer is known (#532): a card not away
  # waits for no card it gave way to (for), and with no other card's live claim nothing below changes what it waits on.
  [ "$away" = '{"for": []}' ] \
    || for=$(for o in $(jq -r '.for[]' <<<"$away"); do [ ! -d "$CARDS/$o" ] || ! ready "$CARDS/$o" || printf '%s\n' "$o"; done | jq -Rsc 'split("\n") | map(select(. != ""))')
  mine=$(git -C "$2" diff --cached --name-only --no-renames -z | jq -Rsc 'split("\u0000") | map(select(. != "" and (endswith(".md") | not)))') || return 1
  # Each live claim, the card's own pid read with it: "<pid> <claim>". Not of a card stacked on this one (its worktree on
  # the stack's base, stackto()): it lands after this one, so this one never waits on it.
  others=$(for o in "$CARDS"/*.claim; do
      [ -e "$o" ] && [ "$o" != "$2.claim" ] || continue
      c=${o##*/}
      [ ! -e "${o%.claim}.stack" ] || ! jq -e --arg me "$1" --arg h "$(git -C "${o%.claim}" rev-parse HEAD 2>/dev/null)" '.on == $me and .base == $h' "${o%.claim}.stack" >/dev/null 2>&1 || continue
      o=$(jq -r --arg c "${c%.claim}" 'select((.pid | type) == "number" and (.paths | type) == "array") | "\(.pid) \(. + {card: $c} | tojson)"' "$o" 2>/dev/null) || continue
      [ -z "$o" ] || ! kill -0 "${o%% *}" 2>/dev/null || printf '%s\n' "${o#* }"
    done) || return 1
  [ -z "$others" ] && others='[]' || others=$(jq -sc . <<<"$others") || return 1
  # Cards whose change applies together with this one are no overlap: left out here, as if they shared no file.
  git -C "$2" diff --cached --binary --no-renames > "$2.cpatch.new" || return 1
  if [ "$others" != '[]' ]; then
    apart=$(together "$2.cpatch.new" "$mine" "$others" "$(cardpatch "$2" ':(exclude)*.md')") || return 1
    # A card stacked on another (its worktree on the stack's base, stackto()): its change applies on that card's, and
    # it lands only after it, so it waits on it still; but not on that card away for a fix round (giveway()): for the
    # fix of its failed tests (fixing), or, once its own tests passed on the change it holds (testedhere()), for the
    # fix of its review's findings (fix; the owner, 2026-11-17). It is fitted onto main alone then, and lands.
    stk=$(jq -r --arg h "$(git -C "$2" rev-parse HEAD 2>/dev/null)" 'select(.base == $h) | .on' "$2.stack" 2>/dev/null) || stk=''
    if [ -n "$stk" ]; then
      t=false; ! jq -e --arg s "$stk" 'any(.[]; .card == $s and .away == true and .fix == true)' <<<"$others" >/dev/null || ! testedhere "$2" || t=true
      apart=$(jq -c --arg s "$stk" 'map(select(. != $s))' <<<"$apart") \
        && others=$(jq -c --arg s "$stk" --argjson t "$t" 'map(select(.card != $s or .away != true or (.fixing != true and (.fix != true or ($t | not)))))' <<<"$others") || return 1
    fi
    [ "$apart" = '[]' ] || others=$(jq -c --argjson a "$apart" 'map(select(.card | IN($a[]) | not))' <<<"$others") || return 1
    ready "$2" || notready=1
    if jq -e --argjson m "$mine" 'any(.[]; .away == true and .back != true and (.paths - (.paths - $m)) != [])' <<<"$others" >/dev/null && [ $notready = 1 ]; then
      others=$(jq -c 'map(if .away != true then . elif .back != true then .held = true else empty end)' <<<"$others")
    else others=$(jq -c 'map(select(.away != true))' <<<"$others"); fi
    # Ready, it does not wait behind a waiting card that shares its files and is not ready (it may wait on a card away).
    [ $notready = 1 ] || unready=$(jq -r --argjson m "$mine" '.[] | select(.held != true and (.paths - (.paths - $m)) != []) | .card' <<<"$others" \
      | while IFS= read -r o; do [ ! -d "$CARDS/$o" ] || ready "$CARDS/$o" || printf '%s\n' "$o"; done | jq -Rsc 'split("\n") | map(select(. != ""))')
    # When its tests passed (ms, readysince(); null when they have not or its change no longer fits main), and those of
    # each card that shares its files (rdy: {card: since}), for which goes first.
    [ $notready = 1 ] || ms=$(readysince "$2") || ms=null
    rdy=$(jq -r --argjson m "$mine" '.[] | select((.paths - (.paths - $m)) != []) | .card' <<<"$others" \
      | while IFS= read -r o; do ! t=$(readysince "$CARDS/$o") || printf '%s\t%s\n' "$o" "$t"; done \
      | jq -Rsc 'split("\n") | map(select(. != "") | split("\t") | {(.[0]): (.[1] | tonumber)}) | add // {}') || return 1
  fi
  w=$(stdb ask lines cards | jq -cn --argjson mine "$mine" --argjson o "$others" --arg me "$1" --argjson ord "$ord" --argjson for "$for" --argjson un "$unready" --argjson ms "$ms" --argjson rdy "$rdy" \
      '[inputs] as $all | [$all[] | select(.step == "picked")] as $p | ($p | map(.card)) as $order | ($ord | length) as $n
      | [$all[] | select(.step | IN("landed", "closed", "blocked")) | .card] as $ended
      | def at($c): $order | index($c) // -1;
        def rank($c): ($p | map(select(.card == $c)) | first | .issue) as $i | ($ord | index($i)) // $n;
        def rs($c): if $c == $me then $ms else $rdy[$c] end;
        def key($c): [rank($c), (rs($c) == null), (rs($c) // 0), at($c)];
      rank($me) as $r
      # A holder it goes past as a ready card (fit): of its rank, its tests not passed, or passed after its own.
      | def fit($c): $ms != null and rank($c) == $r and key($c) > key($me);
      [$o[] | select(at(.card) >= 0 and (.card | IN($ended[]) | not)) | . + {shared: (.paths - (.paths - $mine))} | select(.shared != [])] as $s
      | ([$s[] | select(if .held == true then ($r == $n or rank(.card) < $n) and (fit(.card) | not) else key(.card) < key($me) and (rank(.card) < $r or (.card | IN($un[]) | not)) or (.card | IN($for[])) and rank(.card) <= $r end)]
        | min_by(key(.card))) as $w
      | if $w then {on: $w.card, paths: $w.shared} else {past: [$s[] | select(.held == true and (fit(.card) | not)) | .card], fit: [$s[] | select(.held == true and fit(.card)) | .card]} end') || return 1
  # w is {"on":…} (the card it waits on) or {"past":[…],"fit":[…]} (the cards it went past, as an ordered card and as
  # a ready one), as jq -c prints them. One an ordered card went past is reviewed again (was, settle()); one only ready
  # cards went past is marked fit, and is not.
  case $w in
    '{"on":'*) ;;
    *) [ "$w" = '{"past":[],"fit":[]}' ] || for o in $(jq -r '.past[]?' <<<"$w"); do
         { jq -c '. + {passed: true} | del(.fit)' "$CARDS/$o.claim" > "$CARDS/$o.claim.new" && mv -f "$CARDS/$o.claim.new" "$CARDS/$o.claim"; } 2>/dev/null || :
       done
       [ "$w" = '{"past":[],"fit":[]}' ] || for o in $(jq -r '.fit[]?' <<<"$w"); do
         { jq -c '.fit = (.passed != true or .fit == true) | .passed = true' "$CARDS/$o.claim" > "$CARDS/$o.claim.new" && mv -f "$CARDS/$o.claim.new" "$CARDS/$o.claim"; } 2>/dev/null || :
       done
       w='' ;;
  esac
  passed=$(jq -c '.passed == true' "$2.claim" 2>/dev/null) || passed=false
  fit=$(jq -c '.passed == true and .fit == true' "$2.claim" 2>/dev/null) || fit=false
  gave=$(jq -c '.gave // 0 | numbers' "$2.claim" 2>/dev/null) && [ -n "$gave" ] || gave=0
  jq -cn --argjson p "$3" --argjson m "$mine" --argjson h "$([ -z "$w" ] && echo true || echo false)" --argjson was "$passed" --argjson f "$fit" --argjson g "$gave" --argjson a "$away" \
    '{pid: $p, paths: $m, held: $h, gave: $g} + if $h then {was: ($was and ($f | not))} else {passed: $was} + (if $f then {fit: true} else {} end) + (($a | select(.away) | . + {back: true}) // {}) end' > "$2.claim.new" && mv -f "$2.cpatch.new" "$2.cpatch" && mv -f "$2.claim.new" "$2.claim" || return 1
  if [ -z "$w" ] && [[ ${1##*-} =~ ^[0-9]+$ ]]; then
    for o in "$CARDS"/*.claim; do
      c=${o##*/}
      [ -e "$o" ] && [ "$o" != "$2.claim" ] && { [ "$apart" = '[]' ] || ! jq -e --arg c "${c%.claim}" 'index($c)' <<<"$apart" >/dev/null; } || continue
      { jq -e --argjson m "$mine" '.away == true and .to == null and (.paths | type) == "array" and (.paths - (.paths - $m)) != []' "$o" >/dev/null \
        && jq -c --argjson to $((10#${1##*-})) '.to = $to' "$o" > "$o.new" && mv -f "$o.new" "$o"; } 2>/dev/null || :
    done
  fi
  printf '%s' "$w"
}

# Whether <patch> fits onto the index GIT_INDEX_FILE names, and puts it there: applied as it is, or, where that fails, a
# three-way merge that leaves no conflict and the same change, its own added and removed lines being <id> (cardpatch()).
# A merge that leaves another change does not fit: a change main holds already merges to nothing. The git apply options
# go to both tries. What git apply prints of the merge goes to stderr. The patch is named by its absolute path.
fits() { # <patch> <id> [git apply option...]
  local t
  git apply --cached "${@:3}" "$1" 2>/dev/null && return 0
  t=$(git write-tree) && merge3 "${@:3}" "$1" || return 1
  [ -n "$2" ] && { t=$(git diff --cached --binary --no-renames -U0 "$t" | git patch-id --stable); [ "${t%% *}" = "$2" ]; } \
    || { echo "its three-way merge does not leave the card's own change: main holds it already, or another like it" >&2; return 1; }
}
# git apply --cached --3way onto the index GIT_INDEX_FILE names, with an empty work tree of its own: git writes a file it
# merges into the work tree even with --cached (one the index holds already), and main's checkout is no place for it.
merge3() { # [git apply option...] <patch, by its absolute path>
  local w rc
  w=$(mktemp -d) || return 1
  GIT_DIR=$(git rev-parse --absolute-git-dir) GIT_WORK_TREE=$w git -C "$w" apply --cached --3way "$@"; rc=$?
  rm -rf "$w"; return $rc
}
# Whether the change staged at <worktree> differs from <tree>, a three-way merge with its conflict markers in it, only
# inside its conflicts: in the files that conflict, one a line, and there only from a `<<<<<<< ` line to its `>>>>>>> `
# line (a line added just before or after one is the same text as one added inside it). Everywhere else the card's
# change is the merge's. A file whose name holds a new line, a binary change, or a change of mode (a header line of
# the diff other than its `diff --git`, `index`, `---` and `+++` lines) counts as outside.
inconflicts() { # <worktree> <tree> <files that conflict>
  local f fs
  mapfile -d '' fs < <(git -C "$1" diff --cached --name-only --no-renames -z "$2") && wait $! || return 1
  for f in "${fs[@]}"; do
    grep -qxF -- "$f" <<<"$3" || return 1
    awk 'NR == FNR { if (/^<<<<<<< /) a = FNR; else if (/^>>>>>>> / && a) { s[++n] = a; e[n] = FNR; a = 0 }; next }
      !/^(diff --git |index |--- |\+\+\+ |@@ |[-+\\])/ { out = 1 }
      /^@@ / { split(substr($2, 2), o, ","); b = o[1] + 0; c = (2 in o) ? o[2] + 0 : 1; h++; ok = 0
        for (i = 1; i <= n; i++) if (c ? b >= s[i] && b + c - 1 <= e[i] : b >= s[i] - 1 && b <= e[i]) ok = 1
        if (!ok) out = 1 }
      END { exit out || !h }' <(git -C "$1" show "$2:$f" 2>/dev/null) <(git -C "$1" diff --cached --no-renames --no-color -U0 "$2" -- ":(literal)$f") || return 1
  done
}

# Test files at landing (settle()). A three-way merge of the card's change (<worktree>.patch) onto main, the worktree's
# HEAD, that left a conflict in a test file the change names (one of <test files>: a test file by the pack's
# tests.patterns, testpaths() in issues.sh, and with a name plain enough to write as a gitattributes pattern) is made again keeping both sides of those files' conflicts, main's then the card's (git's
# union merge). It fits when that leaves no conflict, in a code file either, and a change that is not empty and
# whose lines outside the test files the change names are the card's own (<id>: unionx() of the change as it was).
# The worktree is left as the merge left it.
unionfit() { # <worktree> <files that conflict, one a line> <test files, one a line> <id>
  local a f rc
  a=$(mktemp) || return 1
  while IFS= read -r f; do ! grep -qxF -- "$f" <<<"$3" || printf '"/%s" merge=union\n' "$f"; done <<<"$2" > "$a"
  [ -s "$a" ] && git -C "$1" -c core.attributesFile="$a" apply --3way --index "$1.patch" >/dev/null 2>&1; rc=$?
  rm -f "$a"
  [ $rc = 0 ] && ! git -C "$1" diff --cached --quiet && [ "$(unionx "$1" "$3")" = "$4" ]
}
# The fast resolver (the owner, 2026-11-18, #381): a three-way merge of the card's change (<worktree>.patch) onto main
# that left conflicts is first given to one judge call (judgecall(), lib/review.sh: the judge seat, no tools), with the
# judge on in the control record: only the conflicts (diff3 style, the base between the two sides) and a few lines
# around each go to it, numbered by lib/fastfit.py, and it answers with the merged text of each. That text is written in
# their place. It fits when no conflict marker is left, the lines changed are only inside the conflicts (inconflicts())
# and a change is left. Else, or when the call fails, the worktree is put back on <onto> and the session fits the card,
# as before. The merged files' parse check and the card's tests run before it lands; it is not reviewed again.
FASTFIT_ASK='Two changes to the same lines of code clash in a three-way merge. In each conflict below, the lines from `<<<<<<< ours` to `|||||||` are main as it is now (another change already landed), the lines from `|||||||` to `=======` are the base both changes started from, and the lines from `=======` to `>>>>>>> theirs` are the card'"'"'s change. Write, for each conflict, the lines that keep both changes: what main added or changed and what the card added or changed. Keep the code style. Do not read or change any file. Answer with one JSON object and nothing else: each key a conflict'"'"'s number as a string, each value the text that replaces that whole conflict, its markers included, with no markers in it. Give every conflict a value.'
fastfit() { # <worktree> <files that conflict, one a line> <onto: main's commit> <the merge with its conflict markers, a tree>
  local d f q rc=1
  judgeon >/dev/null 2>&1 && [ -n "$2" ] && [ -n "$4" ] && d=$(mktemp -d) || return 1
  printf '%s\n' "$2" > "$d/files"
  # The merge again, its conflicts marked diff3 style, the files saved before the judge call puts the worktree back.
  git -C "$1" -c merge.conflictStyle=diff3 apply --3way --index "$1.patch" >/dev/null 2>&1
  while IFS= read -r f; do mkdir -p "$d/t/$(dirname "$f")" && cp -- "$1/$f" "$d/t/$f" || break; done <<<"$2"
  if [ -z "$f" ] || [ -f "$d/t/$f" ]; then
    git -C "$1" reset -q --hard "$3" 2>/dev/null && q=$(python3 "$HERE/lib/fastfit.py" prompt "$d/t" "$d/files" 2>/dev/null) \
      && CALLSTEP=fix CALLACT='the fast resolver merges the conflicts' judgecall "$1" "$FASTFIT_ASK" "$q" >/dev/null 2>&1 \
      && { git -C "$1" -c merge.conflictStyle=diff3 apply --3way --index "$1.patch" >/dev/null 2>&1; :; } \
      && python3 "$HERE/lib/fastfit.py" apply "$1" "$d/t" "$d/files" "$1.judge" 2>/dev/null \
      && git -C "$1" add -A 2>/dev/null \
      && ! git -C "$1" diff --cached -U0 | grep -qE '^\+(<{7}|\|{7}|={7}|>{7})( |$)' \
      && inconflicts "$1" "$4" "$2" && ! git -C "$1" diff --cached --quiet && rc=0
  fi
  rm -rf "$d"
  [ $rc = 0 ] || git -C "$1" reset -q --hard "$3" 2>/dev/null
  return $rc
}
# After a merge at landing (settle(): a clean three-way merge, a union merge or the session that brings the card onto
# main; card(): the rebuild and the port), before any test runs: every file the staged change at <worktree> changes
# and keeps still parses (git called #415's merge clean, and it left a test file with two openings and one end). A file
# is checked by the command of each glob it matches (a glob's * matches a / too), of PARSE and of the pack's land.parse
# (a glob there replaces the same glob here), run in the worktree with the file's path added after it. Prints, for each
# file that fails, the file, the command and the first 20 lines of its output, and returns 1 when one does; 2, saying
# why, when the check cannot be made (the pack or the change cannot be read).
PARSE='{"*.js": "node --check", "*.mjs": "node --check", "*.sh": "bash -n", "*.json": "jq empty", "*.py": "python3 -m py_compile"}'
parses() { # <worktree>
  local p fs f i out d rc=0
  packget land.parse p && mapfile -d '' p < <(jq -j --argjson d "$PARSE" '$d + . | to_entries[] | .key, "\u0000", .value, "\u0000"' <<<"$p") \
    && [ $((${#p[@]} % 2)) = 0 ] && [ ${#p[@]} -gt 0 ] || { echo "the pack's land.parse could not be read"; return 2; }
  mapfile -d '' fs < <(git -C "$1" diff --cached --name-only --no-renames --diff-filter=d -z HEAD) && wait $! \
    || { echo "the files of the card's change could not be read"; return 2; }
  # py_compile writes its .pyc beside the file unless told where: a folder of its own, so the worktree gains no file.
  d=$(mktemp -d) || { echo "no temporary folder could be made"; return 2; }
  for f in "${fs[@]}"; do
    for ((i = 0; i < ${#p[@]}; i += 2)); do
      # shellcheck disable=SC2053 # the glob is a pattern
      [[ $f == ${p[i]} ]] || continue
      out=$(cd "$1" && PYTHONPYCACHEPREFIX=$d sh -c "${p[i + 1]} \"\$1\"" parse "./$f" 2>&1 </dev/null) && continue
      rc=1; printf '%s: `%s` failed:\n%s\n' "$f" "${p[i + 1]}" "$(head -n 20 <<<"$out")"
    done
  done
  rm -rf "$d"; return $rc
}
# The staged change at <worktree>'s own added and removed lines (cardpatch()) outside <test files> (one a line).
unionx() { # <worktree> <test files>
  local x
  mapfile -t x < <(sed 's/^/:(exclude,literal)/' <<<"$2")
  cardpatch "$1" "${x[@]}"
}

# The cards of <claims json> that share a file with <paths json> yet do not overlap the change in <patch>, whose own
# lines are <id> (cardpatch()): that patch fits (fits()) onto main with the card's own change, as it stood at its claim
# (<worktree>.cpatch), already merged there three-way, as ready() and the landing fit a change onto main. Their
# documentation files (*.md) are left out of both, as claim() leaves them out (and <id> too). Printed as a json list of
# cards. A card whose change does not merge onto main, or that has no such patch, overlaps on any shared file. The patch
# of a card that tests a batch is the whole batch's change (gather()).
together() { # <patch> <paths json> <claims json> <id>
  local d o
  d=$(mktemp -d) || return 1
  if GIT_INDEX_FILE=$d/main git read-tree "refs/heads/$BRANCH" 2>/dev/null; then
    for o in $(jq -r --argjson m "$2" '.[] | select((.paths - (.paths - $m)) != []) | .card' <<<"$3"); do
      [ -e "$CARDS/$o.cpatch" ] && cp "$d/main" "$d/index" && GIT_INDEX_FILE=$d/index merge3 --exclude='*.md' "$CARDS/$o.cpatch" >/dev/null 2>&1 \
        && GIT_INDEX_FILE=$d/index fits "$1" "$4" --exclude='*.md' >/dev/null 2>&1 && printf '%s\n' "$o"
    done
  fi | jq -Rsc 'split("\n") | map(select(. != ""))'
  rm -rf "$d"
}

# Whether the staged change of the card at <worktree> fits onto main as it is now (fits(): a three-way merge that
# leaves no conflict and the same change counting, as settle() fits it): whether it is ready to land. Only a private
# index is written.
ready() { # <worktree>
  local d rc
  d=$(mktemp -d) || return 1
  GIT_INDEX_FILE=$d/index git read-tree "refs/heads/$BRANCH" 2>/dev/null && git -C "$1" diff --cached --binary --no-renames > "$d/patch" \
    && GIT_INDEX_FILE=$d/index fits "$d/patch" "$(cardpatch "$1")" >/dev/null 2>&1; rc=$?
  rm -rf "$d"; return $rc
}
# Whether a card's change that clashes with main as it is now clashes in documentation files (*.md) alone: its change
# outside them (<id>: cardpatch() of it) fits onto main (fits()). Only a private index is written.
docsonly() { # <patch of its change, by its absolute path> <id>
  local d rc
  [ -n "$2" ] && d=$(mktemp -d) || return 1
  GIT_INDEX_FILE=$d/index git read-tree "refs/heads/$BRANCH" 2>/dev/null && GIT_INDEX_FILE=$d/index fits "$1" "$2" --exclude='*.md' >/dev/null 2>&1; rc=$?
  rm -rf "$d"; return $rc
}

# A card that holds its files and cannot land as it is (its change no longer applies to main, or it is to be reviewed,
# fixed or tested again) gives up its turn for that time: its claim is marked away, so it holds nothing (claim()),
# and a card that is ready lands meanwhile; it claims again when it is ready (settle()), after the cards
# that were waiting for its files then (for). gave counts its give-ways; one that has given way GIVEWAY times keeps
# its claim, as before give-ways (not for a fix round while a card is stacked on it, stackto()): returns 1 then, and when
# it holds nothing to give. fixing marks a give-way for the
# fix of the card's failed tests, for the Board; fix one for the fix of its review's findings.
GIVEWAY=3
giveway() { # <card> <worktree> [fixing|fix]; under the lock
  local o f='[]' s=false
  # A card stacked on this one (stackto()) goes on once this one gives way for a fix round (claim()): that give-way is
  # not capped, and a claim already away (given way to be fitted, reviewed or tested again) is marked for that round.
  if [ -n "${3:-}" ] && jq -e --arg c "$1" 'select(.on == $c)' "$CARDS"/*.stack >/dev/null 2>&1; then
    s=true
    if jq -e '.away == true' "$2.claim" >/dev/null 2>&1; then
      jq -c --arg x "$3" '.[$x] = true' "$2.claim" > "$2.claim.new" && mv -f "$2.claim.new" "$2.claim"; return 1
    fi
  fi
  jq -e --argjson n "$GIVEWAY" --argjson s "$s" '.held == true and ((.gave // 0) < $n or $s)' "$2.claim" >/dev/null 2>&1 || return 1
  for o in "$CARDS"/*.claim; do
    [ -e "$o" ] && [ "$o" != "$2.claim" ] || continue
    jq -e --slurpfile me "$2.claim" '(.pid | type) == "number" and .held != true and .away != true and (.paths | type) == "array"
      and (.paths - (.paths - $me[0].paths)) != []' "$o" >/dev/null 2>&1 && kill -0 "$(jq -r .pid "$o")" 2>/dev/null || continue
    f=$(jq -c --arg c "$(basename "$o" .claim)" '. + [$c]' <<<"$f")
  done
  jq -c --argjson f "$f" --arg x "${3:-}" '{pid, paths, held: false, away: true, gave: ((.gave // 0) + 1), for: $f, to: null, fixing: ($x == "fixing"), fix: ($x == "fix")}' "$2.claim" > "$2.claim.new" && mv -f "$2.claim.new" "$2.claim"
}

# Stacking (the owner, 2026-11-17: a card waited 4 hours on a holder that looped through its fixes). With batches on
# (the pack's landBatch over 1), a card that claim() tells to wait on card H does not sleep: its change is fitted at
# once onto main plus H's kept change (H's <worktree>.cpatch, made a commit of its own: the stack's base), as settle()
# fits a change onto main, with the one session it would need after H lands anyway, and it is reviewed and tested
# there. It then waits on H at its claim as before (claim() does not count H as applying together with it), and a batch
# H takes it into lands both, H first (gather()). When H fails its tests (H gives way for their fix), the card waits no
# more: it is fitted onto main alone and lands, and H is brought onto it after its fix. When H's kept change changes
# after the stack (or the card is to wait on another card), the card is stacked again once; after that it waits, as a
# card did before stacking. A card whose
# issue names H's in a `Depends on:` line only waits. Nor is a card stacked on an H of its rank in the control record's
# order list (claim()) whose tests have not passed (readysince()): it waits running its own on main (settle()), and
# once they passed it goes past H and lands first (claim(): a ready card lands first). <worktree>.stack: {on: H, id: git patch-id of H's change at the
# stack, base: the base commit, restacks}. Prints the base when the card is to be stacked now; else returns 1.
stackto() { # <card> <worktree> <claim()'s wait> <issue json>
  local h n id s d b rc o
  h=$(jq -r .on <<<"$3") && [[ ${h##*-} =~ ^[0-9]+$ ]] && [[ ${1##*-} =~ ^[0-9]+$ ]] && packget landBatch n && [ "$n" -gt 1 ] || return 1
  jq -e --argjson h $((10#${h##*-})) "$DEPS"' needs | index($h) | not' <<<"$4" >/dev/null 2>&1 || return 1
  if ! readysince "$CARDS/$h" >/dev/null; then
    o=$(ctl 2>/dev/null) && o=$(jq -c '.order | arrays' <<<"$o") && [ -n "$o" ] || o='[]'
    jq -e --argjson a $((10#${1##*-})) --argjson b $((10#${h##*-})) '(index($a) // -1) != (index($b) // -1)' <<<"$o" >/dev/null || return 1
  fi
  d=$(mktemp -d) || return 1
  cp "$CARDS/$h.cpatch" "$d/patch" 2>/dev/null && id=$(git patch-id --stable < "$d/patch") && id=${id%% *} && [ -n "$id" ] || { rm -rf "$d"; return 1; }
  n=0; s=$(jq -c objects "$2.stack" 2>/dev/null) || s=''
  if [ -n "$s" ]; then
    jq -e --arg h "$h" --arg id "$id" '.on != $h or .id != $id' <<<"$s" >/dev/null && n=$(jq '(.restacks // 0) + 1' <<<"$s") && [ "$n" -le 1 ] || { rm -rf "$d"; return 1; }
  fi
  GIT_INDEX_FILE=$d/index git read-tree "refs/heads/$BRANCH" 2>/dev/null \
    && { GIT_INDEX_FILE=$d/index git apply --cached "$d/patch" 2>/dev/null || GIT_INDEX_FILE=$d/index merge3 "$d/patch" >/dev/null 2>&1; } \
    && b=$(GIT_INDEX_FILE=$d/index git write-tree 2>/dev/null) && b=$(git commit-tree "$b" -p "refs/heads/$BRANCH" -m "conveyor: main with the change of card $h" 2>/dev/null) \
    && jq -cn --arg h "$h" --arg id "$id" --arg b "$b" --argjson n "$n" '{on: $h, id: $id, base: $b, restacks: $n}' > "$2.stack" && printf '%s\n' "$b"; rc=$?
  rm -rf "$d"; return $rc
}

# After its review, before landing (at claim()): the card waits while claim() says so, its live record naming that card and the files and a start line of <step> standing,
# unless it is stacked on that card (stackto(): fitted as below onto the stack's base, not main, it returns 2). Then, when main has
# moved since its change was made, it goes on from main as it is now: its patch applied there, or merged there
# three-way with no conflict left and the same change (fits()), or its test files' conflicts merged keeping both
# sides (unionfit(): its tests then run again), or, when that fails too, brought there by one session
# (step fix). A card that can give way (giveway()) does so for that session and returns 2 after it: reviewed again, it claims again. One that keeps its claim claims and checks again after it. A card
# has one such session (the landing's one rebuild included: card()'s caught), and one more each time a card took the
# turn it gave up, or whose tests failed and are run again on main as it is now (card() clears caught there, #582):
# main can move during each one, so after it a change that no longer applies is put back as it was and meets the
# conflict at landing, as before. Returns 1 when it blocked the card, 2 when a session changed the
# card's change outside documentation (*.md) or when main moved after an ordered card went past the card at its last
# claim (it needs a review),
# 3 when a batch landed it, 4 when its own tests failed while it waited or it broke a batch's tests (card()'s trc
# and sec say how), else 0. Each merge here (a clean three-way one, a union one, or the session's) sets parsecheck:
# card() then checks that the merged files parse (parses()) before any test runs.
settle() { # <card> <issue> <worktree> <the sessions' prompt> <step it waits to begin> <issue json>; sets card()'s caught, trc, sec, waitsec, behind and parsecheck
  local me=$BASHPID w waited='' ws wb old err t moved=0 away b out id mt cf tf ix docs dp onto stk
  ! jq -e '.away == true and (.to | type) == "number"' "$3.claim" >/dev/null 2>&1 || caught=''
  while :; do
    # In a wait, what the card has waited is brought up to date each time round, the last one of the wait too: a wait
    # that ends between two looks counts whole. A ready card's <worktree>.ready carries it too (extra.waitSec, with
    # card()'s mainsec): a batch that lands it writes its landed line from that extra (fives()), for the drift watch.
    if [ -n "$waited" ]; then
      waitsec=$((wb + SECONDS - ws))
      [ ! -e "$3.ready" ] || { jq -c --argjson w "$((waitsec + ${mainsec:-0}))" '.extra.waitSec = $w' "$3.ready" > "$3.ready.new" && mv -f "$3.ready.new" "$3.ready"; } || rm -f "$3.ready.new"
    fi
    # A change a session changed here is reviewed again before it lands: no batch takes it till then (gather()).
    [ $moved = 0 ] || rm -f "$3.ready"
    # The card records kept in this shell (stdb, lib/records.sh): a look that finds them unchanged asks no database.
    stdb ask lines cards >/dev/null 2>&1 || :
    w=$(locked claim "$1" "$3" "$me") || { rm -f "$3.idle"; block "$1" "$2" "$3" "$5: the engine could not write the claim on the files of the card"; return 1; }
    # While it only sleeps out a wait, on a card or on the batch card that took it, <worktree>.idle stands: the loop
    # does not count the card against the builder cap then (idle(), lib/run.sh). It goes before any work of the card.
    # Taken into a batch (gather()): it waits for the card that took it, which lands it (3) or finds it breaks the
    # batch's tests (4). A batch whose card is gone takes it no more.
    if [ -e "$3.batch" ]; then
      b=$(jq -c objects "$3.batch" 2>/dev/null) || b='{}'
      ! jq -e .landed <<<"$b" >/dev/null 2>&1 || { rm -f "$3.idle"; return 3; }
      # That run was the batch card's: its wait and run are not known here (testrec()).
      ! jq -e .fail <<<"$b" >/dev/null 2>&1 || { trc=$(jq -r .fail <<<"$b"); sec=$(jq -r '.sec // 0' <<<"$b"); TEST_WAIT=''; TEST_RUN=''; TEST_FREE=''; rm -f "$3.batch" "$3.idle"; return 4; }
      if kill -0 "$(jq -r '.pid // 0' <<<"$b")" 2>/dev/null; then [ -n "$w" ] || { : > "$3.idle"; sleep "$LIVE"; continue; }; else rm -f "$3.batch"; fi
    fi
    # Told to wait, it is stacked on that card instead when it can be (stackto()): fitted below onto the stack's base
    # (onto), not main, and reviewed there; not while a batch holds it.
    stk=''
    if [ -n "$w" ] && [ ! -e "$3.batch" ] && onto=$(stackto "$1" "$3" "$w" "$6"); then
      stk=$(jq -r .on <<<"$w"); w=''; echo "conveyor: card $1 is stacked on card $stk, which changes the same files: it is fitted onto main with that card's change"
    else onto=refs/heads/$BRANCH; fi
    if [ -n "$w" ]; then
      # Each wait begins with its start line, one after a session of this call too (a card that kept its claim through
      # the session that brought it onto main): `health` counts a wait whose start line is the card's last.
      [ -n "$waited" ] || { waited=$(date -u +%FT%TZ); ws=$SECONDS; wb=$waitsec
        began "$1" "$2" "$5"; echo "conveyor: card $1 waits on card $(jq -r .on <<<"$w"), which changes the same files: $(jq -r '.paths | join(", ")' <<<"$w")"; }
      # The live record names the card it waits on now: one `retry` gives back is picked first, past the cap (urgent).
      # It names too (waited) what the card waited before this wait (before: the seconds of its waits that ended) and
      # every card it has waited on, in order (behind), so `health` can say when all its waits together pass WAIT_LIMIT.
      behind=$(jq -c --argjson w "$w" 'if index($w.on) then . else . + [$w.on] end' <<<"$behind" 2>/dev/null) || behind='[]'
      jq -cn --argjson w "$w" --arg at "$waited" --arg s "$5" --argjson wb "$wb" --argjson bh "$behind" '{step: $s, at: $at, last: (now | todate), turns: 0, waits: $w, waited: {before: $wb, behind: $bh},
        action: "waiting on card \($w.on), which changes the same files: \($w.paths | join(", "))"}' > "$3.live.tmp" 2>/dev/null && mv -f "$3.live.tmp" "$3.live"
      # Waiting after a GO (<worktree>.ready), with batches on, it runs its own product checks and changed tests,
      # holding nothing: only a card whose own tests passed is ready, so no batch lands a card that fails alone. Its
      # checks failing block it, as at its turn; its tests failing send it to its fix (4). Not one merged onto main
      # whose files have not been found to parse (parses()): that check runs first, at its turn (card()). A stacked card
      # (stackto()) is checked here, so it is tested on its base while it waits. On its base, its checks or tests that
      # fail may fail for that card's change, which has not passed its own yet: it is not blocked or fixed for that, but
      # marked (stackred) and waits on, untested; it runs them again where it goes next (fitted onto main once that card
      # landed or failed its tests).
      [ -z "$parsecheck" ] || [ ! -e "$3.stack" ] || ! parses "$3" >/dev/null 2>&1 || parsecheck=''
      if [ -z "$parsecheck" ] && [ -e "$3.ready" ] && ! jq -e '.tested == true or .alone == true or .stackred == true' "$3.ready" >/dev/null 2>&1 && packget landBatch b && [ "$b" -gt 1 ]; then
        rm -f "$3.idle"; sec=$SECONDS; trc=''
        if ! out=$(checks "$3"); then
          trc=1; [ "$(git -C "$3" rev-parse HEAD 2>/dev/null)" = "$(jq -r .base "$3.stack" 2>/dev/null)" ] || { block "$1" "$2" "$3" "a product check failed; nothing landed."$'\n'"$out"; return 1; }
        else began "$1" "$2" test; tests "$3"; trc=$?; fi
        sec=$((SECONDS - sec))
        # Its run did not run or was stopped with the rule Whole suite in a card off (tests(): <worktree>.stop): blocked
        # with that reason, as at its turn (card()).
        [ "$trc" = 0 ] || [ ! -s "$3.stop" ] || { block "$1" "$2" "$3" "test: $(<"$3.stop")"; return 1; }
        if [ "$trc" != 0 ] && [ "$(git -C "$3" rev-parse HEAD 2>/dev/null)" = "$(jq -r .base "$3.stack" 2>/dev/null)" ]; then
          echo "conveyor: card $1: its checks or tests failed on main with the change of card $(jq -r .on "$3.stack"), which has not passed its own yet: it waits on, and runs them again after that card"
          jq -c '. + {stackred: true}' "$3.ready" > "$3.ready.new" && mv -f "$3.ready.new" "$3.ready" || rm -f "$3.ready"
          trc=''; began "$1" "$2" "$5"; continue
        fi
        [ "$trc" = 0 ] || { waitsec=$((wb + SECONDS - ws)); return 4; }
        # Its test files' times go on its test line (slowtests()).
        trc=''; slowtests "$3" || :
        record "$1" "$2" test pass "$(jq -cn --slurpfile x <(testrec "$3" 0 "$sec") --slurpfile r <(firstrun "$3" pass) --slurpfile s <(slowrec "$3") '$x[0] + $r[0] + $s[0]')"
        testrulespass > /dev/null
        tested "$3"; began "$1" "$2" "$5"; continue
      fi
      : > "$3.idle"; sleep "$LIVE"; continue
    fi
    # The wait ended: a later wait of this call begins anew, what the card waited before it counted once.
    rm -f "$3.idle"; [ -z "$waited" ] || { rm -f "$3.live"; waited=''; }
    old=$(git -C "$3" rev-parse HEAD 2>&1) || { block "$1" "$2" "$3" "$5: the engine could not read the commit of the worktree:${old:0:300}"; return 1; }
    [ "$old" != "$(git rev-parse "$onto" 2>/dev/null)" ] || return $moved
    # Stacked, it is reviewed again on the base. A stacked card that waits no more (that card landed, or failed its
    # tests) is not put back on the base it left: a change that no longer applies on main is brought there by a session.
    if [ -n "$stk" ]; then moved=2; caught=''
    elif [ "$old" = "$(jq -r .base "$3.stack" 2>/dev/null)" ]; then caught=''; fi
    # A card an ordered card went past is reviewed again on main as it is now, even when its patch applies there, and
    # even when that card landed before this claim.
    ! jq -e '.was == true' "$3.claim" >/dev/null 2>&1 || moved=2
    id=$(cardpatch "$3")
    # Its change outside documentation (*.md: docs), and as its tests passed on it (dp: testedhere()), for the session below.
    docs=$(cardpatch "$3" ':(exclude)*.md'); dp=''; ! testedhere "$3" || dp=$docs; [ -z "$stk" ] || docs=''
    # The test files the change names (tf: unionfit()), and its own lines outside them (ix).
    tf=$(git -C "$3" diff --cached --name-only --no-renames 2>/dev/null | testpaths | grep -Ex '[A-Za-z0-9 ._/@+,=~-]+'); ix=''
    [ -z "$tf" ] || ix=$(unionx "$3" "$tf")
    err=$(git -C "$3" diff --cached --binary --no-renames > "$3.patch" && printf '%s\n' "$old" > "$3.base" && git -C "$3" reset -q --hard "$onto" 2>&1) \
      || { block "$1" "$2" "$3" "$5: the engine could not move the change of the card onto main:${err:0:300}"; return 1; }
    git -C "$3" apply --index "$3.patch" 2>/dev/null && { rm -f "$3.base"; return $moved; }
    # Where the patch does not apply as it is, a three-way merge that leaves no conflict and the same change fits it as
    # well (fits()): the card's own added and removed lines are what was reviewed and tested, only the lines around
    # them moved, so its review and its tests stand (testedhere(): cardpatch() reads those lines alone). Any other
    # merge is cleared away, back to main.
    git -C "$3" apply --3way --index "$3.patch" >/dev/null 2>&1 && [ -n "$id" ] && [ "$(cardpatch "$3")" = "$id" ] && { parsecheck=1; rm -f "$3.base"; return $moved; }
    # A merge that left conflicts is kept as a tree, its conflict markers in it (mt), with the files that conflict (cf):
    # the session that fits the card onto main is held to them (inconflicts()).
    mt=''; cf=$(git -C "$3" diff --name-only --diff-filter=U -z 2>/dev/null | tr '\0' '\n')
    [ -z "$cf" ] || { git -C "$3" add -A 2>/dev/null && mt=$(git -C "$3" write-tree 2>/dev/null); } || mt=''
    err=$(git -C "$3" reset -q --hard "$onto" 2>&1) \
      || { block "$1" "$2" "$3" "$5: the engine could not remove the three-way merge of the card onto main:${err:0:300}"; return 1; }
    # A conflict in a test file is merged keeping both sides (unionfit()): two cards that both add a case at the end of
    # one test file both land, with no session. Its tests are not taken as passed (testedhere()), so they run again on
    # the merged files before it lands, and two edits to one test that do not work together fail and go to its fix.
    if [ -n "$tf" ] && [ -n "$cf" ]; then
      if unionfit "$3" "$cf" "$tf" "$ix"; then
        [ ! -e "$3.ready" ] || { jq -c 'del(.tested)' "$3.ready" > "$3.ready.new" && mv -f "$3.ready.new" "$3.ready"; } || rm -f "$3.ready"
        parsecheck=1; rm -f "$3.base"; return $moved
      fi
      err=$(git -C "$3" reset -q --hard "$onto" 2>&1) \
        || { block "$1" "$2" "$3" "$5: the engine could not remove the three-way merge of the card onto main:${err:0:300}"; return 1; }
    fi
    # The fast resolver (fastfit()): one judge call merges the conflicts, with no fitting session and no second review
    # (the owner's pick, 2026-11-18): as after a union merge, its tests are not taken as passed (testedhere()), so the
    # merged files' parse check and its tests run on them before it lands.
    if fastfit "$3" "$cf" "$onto" "$mt"; then
      [ ! -e "$3.ready" ] || { jq -c 'del(.tested)' "$3.ready" > "$3.ready.new" && mv -f "$3.ready.new" "$3.ready"; } || rm -f "$3.ready"
      echo "conveyor: card $1: the fast resolver merged its conflicts with main in $(printf '%s' "$cf" | grep -c .) file(s), with no fitting session; its tests run again on the merged files"
      parsecheck=1; rm -f "$3.base"; return $moved
    fi
    if [ -n "$caught" ]; then
      err=$(git -C "$3" reset -q --hard "$old" 2>&1 && git -C "$3" apply --index "$3.patch" 2>&1) \
        || { block "$1" "$2" "$3" "$5: the engine could not put the change of the card back in the worktree:${err:0:300}"; return 1; }
      rm -f "$3.base"; return $moved
    fi
    # Not ready: the card gives way while one session fits it onto main, and is reviewed before it claims again (unless
    # it clashed in documentation alone, docsonly(), and the session left the rest as it was: below).
    docsonly "$3.patch" "$docs" || docs=''
    caught=1; away=''; ! locked giveway "$1" "$3" || away=1; began "$1" "$2" fix
    t=$CAUGHT; [ -z "$stk" ] || t=${STACKED//@CARD@/$stk}
    t=$(session "$3" "$4"$'\n\n'"$t"$'\n\n## The card\'s patch\nThe file '"$3.patch"$', made against commit '"$old"$'.' fix) || {
      # The card's change goes back into the worktree, in place of the half-made one, so block keeps it.
      git -C "$3" reset -q --hard "$old" 2>/dev/null && git -C "$3" clean -fdq 2>/dev/null && git -C "$3" apply --index "$3.patch" 2>/dev/null \
        || t="${t%%$'\n'*} [the engine could not put the change of the card back in the worktree. The kept patch is what the failed session left]$([[ $t != *$'\n'* ]] || printf '\n%s' "${t#*$'\n'}")"
      block "$1" "$2" "$3" "fix: $t"; return 1; }
    # A session that changed only the conflicts merged and did nothing more: its reply is not given the Done-when check
    # (a merge reply leaves out the D<n> lines). One that changed anything else is checked, as any fix session, and its
    # tests run whole, a merge in doubt (<worktree>.whole, tests()): no pass of the change before it is kept (rerunsince()).
    t=$(jq -c --arg s "$stk" '. + {reason: (if $s == "" then "main moved since the card'"'"'s change was made, and the change no longer applied to it"
      else "stacked on card \($s), which changes the same files: the change was brought onto main with that card'"'"'s change" end)}' <<<"$t")
    if [ -n "$mt" ] && git -C "$3" add -A 2>/dev/null && inconflicts "$3" "$mt" "$cf"; then record "$1" "$2" fix ok "$t"
    else rm -f "$3.rerun"; echo 'merge in doubt: the session that brought the change onto main edited it outside the conflicts' > "$3.whole"; checked "$1" "$2" "$3" "$6" "$4" fix "$t" || return 1; fi
    git -C "$3" add -A && ! git -C "$3" diff --cached --quiet || { block "$1" "$2" "$3" "fix: the session that brought the card's change onto main left no change"; return 1; }
    parsecheck=1; rm -f "$3.base"
    # A clash in documentation alone (a README), and a session that changed nothing outside it: the card's review and
    # its test pass stand, so only its product checks run before it lands. It claims again, as one that kept its claim.
    if [ -n "$docs" ] && [ "$(cardpatch "$3" ':(exclude)*.md')" = "$docs" ]; then [ -z "$dp" ] || tested "$3"; continue; fi
    moved=2
    [ -z "$away$stk" ] || return 2
  done
}

# Batches. The test step runs 10 to 25 minutes, so cards that share files and are ready to land land together, on one
# test run. A card ready to land: one whose own product checks and changed tests passed after a GO, its message and
# commit trailers written (<worktree>.ready: {issue, msg, extra, tested, tree and head: the tree and commit they passed on, since: when
# they passed; alone: a card that files a last NO-GO's follow-ups, never in a batch}), gone past by no ordered or ready card since: one that waits at its landing claim (settle(); not one away,
# giveway()), or the card whose turn it is (card()). When a
# card's turn to land comes and it is ready, it takes every ready card that shares a file with it or with one taken
# before it, in turn, up to the pack's landBatch cards in all, never one that shares a file with another card that
# holds it. The batch is in the control record's order first, then by when each card became ready, the card whose
# turn it is among them; a card stacked on a card of the batch (stackto()) after the others, its change being made on
# that card's. That card's claim then holds the files of the whole batch (paths) and keeps the batch's
# change, so no card whose change does not apply with the batch's lands on one of them while the batch is tested (claim()).
# Its own checks and tests passed on what the card's worktree holds now: it is ready (<worktree>.ready, when it has one),
# with what that run passed (units and cases, passlist(); none when it left no list) for a batch that takes it (batchkeep()).
# The identity of a card's staged change, whatever commit it is on: its own added and removed lines, with no line of
# context (-U0), so a change merged three-way onto a main that moved around it is the same change (fits(), settle());
# of the files <pathspec> names when it is given. Empty when the change is.
cardpatch() { local p r; p=$(git -C "$1" diff --cached --binary --no-renames -U0 HEAD -- "${@:2}" 2>/dev/null | git patch-id --stable 2>/dev/null); r=$?; [ -z "$p" ] || printf '%s\n' "${p%% *}"; return $r; } # <worktree> [pathspec...]
tested() { [ ! -e "$1.ready" ] || { jq -c --arg t "$(git -C "$1" write-tree)" --arg h "$(git -C "$1" rev-parse HEAD)" --arg p "$(cardpatch "$1")" --argjson u "$(jq -ce objects "$1.passed" 2>/dev/null || echo null)" \
  'del(.units, .cases) + {tested: true, tree: $t, head: $h, patch: $p, since: now} + if $u then $u | {units, cases} else {} end' "$1.ready" > "$1.ready.new" && mv -f "$1.ready.new" "$1.ready"; } || rm -f "$1.ready"; } # <worktree>
# Whether they passed on the change it holds now: the same staged change, on whatever commit (owner, 2026-11-13: a
# change that passed its tests and still applies to a main that moved is not tested again; each landing made every
# other card run its tests anew, and one card landed per test run), save for sharedtests() below.
testedhere() { jq -e --arg p "$(cardpatch "$1")" '.tested == true and $p != "" and .patch == $p' "$1.ready" >/dev/null 2>&1; } # <worktree>
# When its tests passed (since, tested()), for a card whose tests passed on the change it holds (testedhere()), not on
# a stack's base (stackto(): there they ran with another card's change); fails for any other card (claim()). While its
# worktree is lent to its batch (<worktree>.lent, batch(), rebatch()), the change it holds is its own (bpid()), not the
# batch's the worktree has then: else a later ready card would go past it there, and land() would refuse the batch.
readysince() { # <worktree>
  local s h
  s=$(jq -e 'select(.tested == true) | .since | numbers' "$1.ready" 2>/dev/null) || return 1
  if [ -s "$1.lent" ]; then
    h=$(<"$1.lent") && jq -e --arg p "$(bpid "$1")" '$p != "" and .patch == $p' "$1.ready" >/dev/null 2>&1 || return 1
  else h=$(git -C "$1" rev-parse HEAD 2>/dev/null) && testedhere "$1" || return 1; fi
  ! jq -e --arg h "$h" '.base == $h' "$1.stack" >/dev/null 2>&1 && printf '%s\n' "$s"
}
# The test files that the staged change at <worktree> and the change main made from <the commit its tests ran on> to
# the worktree's HEAD both touch, one a line; fails when there are none, or when HEAD is that commit or none is given.
# The change's: testsel() narrow of it, and the files its runs passed (the units of <worktree>.ready and .bpass,
# passlist()); main's: testsel() narrow of main's change, and the files the test lines of the cards landed in it name
# (times, clocks, why, ranCases): the project's test command may select tests that testsel() does not. Those tests
# ran on neither change with the other: two cards that each passed alone can fail together on main (#334), so they run
# again on the combined code before the card lands (card(), once for its change: #447; rebatch()). Lists that cannot be made count as shared, the
# message saying so: the tests run again.
sharedtests() { # <worktree> <the commit its tests ran on>
  local h a b r
  h=$(git -C "$1" rev-parse HEAD 2>/dev/null) && [ -n "$2" ] && [ "$2" != "$h" ] || return 1
  a=$(testsel "$1" narrow) && b=$(testsel "$1" narrow "$2" "$h") && r=$(git -C "$1" rev-list "$2..$h" 2>/dev/null) \
    && b+=$'\n'$(stdb ask lines cards 2>/dev/null | jq -rRn --arg r "$r" '($r | split("\n")) as $s
      | reduce (inputs | fromjson? | objects) as $l ({l: [], t: []}; if $l.step == "landed" and ($l.sha | IN($s[])) then .l += [$l.card]
          elif $l.step == "test" then .t += [$l] else . end)
      | .l as $l | .t[] | select(.card | IN($l[])) | (.times, .clocks, .why, .ranCases) | objects | keys[]') \
    || { echo "(the test files of the change or of main's could not be listed)"; return 0; }
  comm -12 <({ sed 1d <<<"$a"; cat "$1.ready" "$1.bpass" 2>/dev/null | jq -r '.units[]? | strings | split("\t")[0]' 2>/dev/null; } | sort -u) \
    <(sed 1d <<<"$b" | grep . | sort -u) | grep .
}
# The cards whose landed line names a commit main made from <the commit its tests ran on> to the worktree's HEAD, in
# the order they landed, space-separated: those a card that lands with no second run again names (card(), #447).
landedsince() { # <worktree> <the commit its tests ran on>
  local r
  r=$(git -C "$1" rev-list "$2..HEAD" 2>/dev/null) && [ -n "$r" ] || return 0
  stdb ask lines cards 2>/dev/null | jq -rRn --arg r "$r" '($r | split("\n")) as $s
    | reduce (inputs | fromjson? | objects | select(.step == "landed" and (.sha | IN($s[]))) | .card) as $c ([];
        if IN(.[]; $c) then . else . + [$c] end) | join(" ")'
}
# The run again for <sharedtests() of the card> (card()): the card's list (<worktree>.rerun, which tests() keeps on a
# main that moved, rerunsince()) loses its `pass` and `ok` lines of the shared files and names each as failed with no
# case, so the command runs it whole, though it passed before and main's change alone does not select it. When the
# shared files could not be listed, it loses every `pass` and `ok` line. Each such file that no `fail` line names gets a
# `shared` line too: it runs because main changed what it tests, and its log says so, not that it did not pass (#345).
unshare() { # <worktree> <sharedtests() of it>
  [ -s "$1.rerun" ] || return 0
  awk -F'\t' -v S="$2" 'BEGIN { all = S ~ /^\(/; n = split(S, a, "\n"); for (i = 1; i <= n; i++) if (!all && a[i] != "") s[a[i]] = 1 }
    ($1 == "pass" || $1 == "ok") && (all || ($2 in s)) { d[$2] = 1; next }
    $1 == "fail" { f[$2] = 1; if ($3 == "") delete s[$2] }
    { print } END { for (x in s) { print "fail\t" x; d[x] = 1 } for (x in d) if (!(x in f)) print "shared\t" x }' "$1.rerun" > "$1.rerun.new" && mv -f "$1.rerun.new" "$1.rerun"
}
gather() { # <card> <worktree> <the card's pid>; under the lock: prints the batch's cards in order, one a line (nothing when it takes none), each other one marked taken (<worktree>.batch)
  local max ord o r x m all d
  packget landBatch max && [ "$max" -gt 1 ] && jq -e '.tested == true and .alone != true' "$2.ready" >/dev/null 2>&1 || return 0
  ord=$(ctl 2>/dev/null) && ord=$(jq -c .order <<<"$ord") || ord='[]'
  o=$(for r in "$CARDS"/*.claim; do
      [ -e "$r" ] && [ "$r" != "$2.claim" ] || continue
      r=${r%.claim}; x=$(jq -c objects "$r.ready" 2>/dev/null) || x=''
      r=$(jq -c --arg c "${r##*/}" --argjson x "${x:-null}" --argjson t "$([ -e "$r.batch" ] && echo true || echo false)" --arg s "$(jq -r '.on // empty' "$r.stack" 2>/dev/null)" \
        'select((.pid | type) == "number" and (.paths | type) == "array") | . + {card: $c, ready: $x, taken: $t, stack: $s}' "$r.claim" 2>/dev/null) || continue
      [ -z "$r" ] || ! kill -0 "$(jq -r .pid <<<"$r")" 2>/dev/null || printf '%s\n' "$r"
    done | jq -sc .) && x=$(jq -c --arg c "$1" --slurpfile r "$2.ready" '{card: $c, paths, ready: $r[0]}' "$2.claim") || return 1
  all=$(stdb ask lines cards | jq -cn --argjson o "$o" --argjson me "$x" --argjson ord "$ord" --argjson max "$max" '
      def meets($a; $b): ($a - ($a - $b)) != [];
      def rank: .ready.issue as $i | ($ord | index($i)) // ($ord | length);
      [inputs | select(.step | IN("landed", "closed", "blocked")) | .card] as $ended
      | [$o[] | select(.card | IN($ended[]) | not)] as $o | [$o[] | select(.held == true) | .paths[]] as $held
      | [$o[] | select(.held != true and .passed != true and (.away != true or .back == true) and (.taken | not) and (.ready | type) == "object" and .ready.tested == true and .ready.alone != true
          and (meets(.paths; $held) | not))] | sort_by([rank, .ready.since])
      | {p: $me.paths, b: [], c: .}
      | until((.b | length) >= $max - 1 or (. as $s | [.c[] | meets(.paths; $s.p)] | any | not);
          . as $s | ([.c[] | meets(.paths; $s.p)] | index(true)) as $i | {p: (.p + .c[$i].paths), b: (.b + [.c[$i]]), c: (.c[:$i] + .c[$i + 1:])})
      | select(.b != []) | ([$me] + .b) as $in
      | {paths: (.p | unique), cards: ($in | sort_by([(.stack as $s | $in | any(.card == $s)), rank, .ready.since]) | map(.card))}') || return 1
  [ -n "$all" ] || return 0
  jq -c --argjson p "$(jq -c .paths <<<"$all")" '.paths = $p' "$2.claim" > "$2.claim.new" && mv -f "$2.claim.new" "$2.claim" || return 1
  # The change that claim keeps is now the batch's: each card's staged change on main, in the batch's order, so a card
  # whose change applies with the whole batch does not wait on it (together()). A card whose change does not apply on
  # those before it is left out, as the batch's test run leaves it out (batch()).
  d=$(mktemp -d) || return 1
  GIT_INDEX_FILE=$d/index git read-tree "refs/heads/$BRANCH" 2>/dev/null || x=''
  for m in $(jq -r '.cards[]' <<<"$all"); do
    [ -n "$x" ] && git -C "$CARDS/$m" diff --cached --binary --no-renames > "$d/patch" 2>/dev/null || { x=''; break; }
    GIT_INDEX_FILE=$d/index git apply --cached "$d/patch" 2>/dev/null || :
  done
  [ -n "$x" ] && GIT_INDEX_FILE=$d/index git diff --cached --binary --no-renames "refs/heads/$BRANCH" > "$2.cpatch.new" 2>/dev/null && mv -f "$2.cpatch.new" "$2.cpatch" \
    || rm -f "$2.cpatch" "$2.cpatch.new"
  rm -rf "$d"
  for m in $(jq -r '.cards[]' <<<"$all"); do
    [ "$m" = "$1" ] || jq -cn --arg b "$1" --argjson p "$3" '{by: $b, pid: $p}' > "$CARDS/$m.batch" || continue
    echo "$m"
  done
}
unbatch() { local m; for m in "$@"; do rm -f "$CARDS/$m.batch"; done; } # <card>...: out of the batch; each waits on at its claim, as before
# card()'s batch, its cards out of it (the card itself has no mark). The change the card's claim keeps is its own again,
# not the batch's (gather()): a card stacked on it now (stackto()) is fitted onto main plus this card's change, never
# onto one that holds the stacked card's own change already (it was then sent to a session to fit a change already
# there, and went away while a later card went past it).
unmate() {
  [ ${#mates[@]} = 0 ] || { git -C "$wt" diff --cached --binary --no-renames > "$wt.cpatch.new" && mv -f "$wt.cpatch.new" "$wt.cpatch"; } \
    || rm -f "$wt.cpatch" "$wt.cpatch.new"
  unbatch "${mates[@]}"; mates=()
}
# land()'s five of each card of card()'s batch (mates), in order: the card's own as given, each other's from its
# <worktree>.ready; with skip, the card's own left out. A NUL after each.
fives() { # <card> <issue> <worktree> <commit message> <extra json> [skip]
  local m
  for m in "${mates[@]}"; do
    if [ "$m" = "$1" ]; then [ -n "${6:-}" ] || printf '%s\0' "$1" "$2" "$3" "$4" "$5"
    else printf '%s\0' "$m" "$(jq -r .issue "$CARDS/$m.ready")" "$CARDS/$m" "$(jq -r .msg "$CARDS/$m.ready")" "$(jq -c .extra "$CARDS/$m.ready")"; fi
  done
}
# What a batch run need not run again (the owner, 2026-11-13: a test that passed is not run again; issue #346). Each
# card of the run brings its passes: its own (the units of <worktree>.ready, passlist(), when they passed on the change
# it holds now), and those of the last batch run that passed with it in it (<worktree>.bpass: {cards: each card of
# that run and its change's patch-id, units, cases, by: each card's units of the run}) when each card of that run that
# is in this one still holds the change it held there; of such a run a card brings only its own units (by), not those
# only a card that left selected (issue #354). A pass is kept when no other card of the run has a pass of the same
# case (a pass of a whole file is one of each of its cases), or when one batch run passed it with each card that has one in it. A card with no
# passes (its change changed since they passed, or its run left no list) has its files named `changed`, so the run
# runs every test they select. Prints {keep: the units kept, changed: those files, units: every unit of the cards'
# passes, kept: how many cases the units it keeps hold, each case once however many passes have it (a case unit is
# one; a file passed whole, the cases of its pass that no case unit names, shared among its pass's whole files, the
# remainder one each to the first of them, so a pass kept whole counts every case it had; none when that pass did not
# say how many cases it had; a file kept both whole and case by case, as one pass named its cases and a batch run
# passed it whole, counts the larger of the two, not both), all: whether nothing is left to run}.
# The patch-id of a card's change in its batch (batch(): <worktree>.bpatch), as cardpatch() gives it (no line of
# context, so it is the one in its <worktree>.ready): the patch put, in an index of its own, on the commit it goes on
# (<worktree>.lent, which rebatch() keeps as the worktree moves onto main), else on the worktree's HEAD.
bpid() { # <worktree>
  local i b p r
  b=$(cat "$1.lent" 2>/dev/null) && [ -n "$b" ] || b=HEAD
  i=$(mktemp) || return 1; rm -f "$i"
  GIT_INDEX_FILE=$i git -C "$1" read-tree "$b" 2>/dev/null && GIT_INDEX_FILE=$i git -C "$1" apply --cached < "$1.bpatch" 2>/dev/null \
    && p=$(GIT_INDEX_FILE=$i git -C "$1" diff --cached --binary --no-renames -U0 "$b" 2>/dev/null | git patch-id --stable 2>/dev/null); r=$?
  rm -f "$i"; [ -z "${p:-}" ] || printf '%s\n' "${p%% *}"; return $r
}
batchkeep() { # <card> <worktree> <the run's cards>
  local c=$1 wt=$2 m w ps
  shift 2
  for m in "$@"; do
    w=$CARDS/$m; [ "$m" != "$c" ] || w=$wt
    mapfile -d '' ps < <(git apply --numstat -z "$w.bpatch" 2>/dev/null); ps=("${ps[@]#*$'\t'*$'\t'}")
    jq -cn --arg c "$m" --arg p "$(bpid "$w")" --argjson r "$(jq -ce objects "$w.ready" 2>/dev/null || echo null)" \
      --argjson t "$(jq -ce objects "$w.bpass" 2>/dev/null || echo null)" '{card: $c, patch: $p, ready: $r, bpass: $t, paths: $ARGS.positional}' --args "${ps[@]}" || return 1
  done | jq -cs '
    def file: split("\t")[0];
    def meets($u; $v): ($u | file) == ($v | file) and ($u == $v or ($u | contains("\t") | not) or ($v | contains("\t") | not));
    . as $all
    | [[$all[].bpass | select((.cards | type) == "object" and (.units | type) == "array")] | unique | .[] | . as $r
       | select(all($all[]; ($r.cards[.card] // .patch) == .patch))] as $rs
    | [$all[] | . as $m | {card, paths,
        own: (.ready | if (type) == "object" and .tested == true and $m.patch != "" and .patch == $m.patch and (.units | type) == "array" then . else null end),
        rs: [$rs[] | select(.cards[$m.card] == $m.patch)]}] as $ms
    | [$ms[] | .card as $c | {card, units: ([(.own.units // [])[], (.rs[] | .by[$c] // [])[]] | unique)}] as $sel
    | ([$sel[].units[]] | unique) as $units
    | [$units[] | . as $u | [$sel[] | select(any(.units[]; meets(.; $u))) | .card] as $by
        | select(($by | length) <= 1 or any($rs[]; . as $r | any(.units[]; . == $u or . == ($u | file)) and all($by[]; $r.cards[.] != null)))] as $keep
    | ([$ms[] | select(.own == null and .rs == []) | .paths[]] | unique) as $ch
    | {keep: $keep, changed: $ch, units: $units,
       kept: (([$ms[].own | objects] + $rs | reduce (.[] | . as $p | [.units[] | select(contains("\t") | not)] as $w
           | ((.units | length) - ($w | length)) as $n
           | (if ($p.cases | type) == "number" then [$p.cases - $n, 0] | max else 0 end) as $m | .units[] | . as $u
           | {k: ., v: (if contains("\t") then 1 else ($m / ($w | length) | floor) + (if ($w | index($u)) < $m % ($w | length) then 1 else 0 end) end)})
           as $e ({}; .[$e.k] = ([.[$e.k] // 0, $e.v] | max))) as $wt
         | [$keep | group_by(file)[] | [(.[] | select(contains("\t") | not) | $wt[.] // 0), (map(select(contains("\t")) | $wt[.] // 0) | add // 0)] | max]
         | add // 0),
       all: ($ch == [] and ($keep | length) == ($units | length))}'
}
# The list a batch run is given (CONVEYOR_TEST_RERUN, tests()): what batchkeep() keeps, as `pass` (a whole file) and
# `ok` (a case) lines, and its `changed` files. A file every unit of which it keeps is one `pass` line, not its cases'
# `ok` lines: a command that cannot run a file's cases apart (any shell test but the engine's runner) honours only
# `pass`, and would run whole again a file passed whole that it kept case by case. None when it keeps nothing and
# names no file: the run's own list stands.
batchlist() { # <worktree> <batchkeep() of the run>
  local p
  jq -e '.keep != [] or .changed != []' <<<"$2" >/dev/null || return 0
  p=$(git -C "$1" diff --cached --binary --no-renames HEAD 2>/dev/null | git hash-object --stdin) || return 1
  { printf 'change\t%s\nbase\t%s\ntree\t%s\n' "$p" "$(git -C "$1" rev-parse -q --verify HEAD 2>/dev/null)" "$(git -C "$1" write-tree 2>/dev/null)"
    jq -r 'def file: split("\t")[0]; . as $k
      | ([$k.keep[] | file] | unique[] as $f | [$k.keep[] | select(file == $f)] as $kf
         | if ([$k.units[] | select(file == $f)] - $kf) == [] then "pass\t" + $f
           else $kf[] | if contains("\t") then "ok\t" + . else "pass\t" + . end end),
        (.changed[] | "changed\t" + .)' <<<"$2"; } > "$1.rerun.new" \
    && mv -f "$1.rerun.new" "$1.rerun"
}
# A batch run that passed (or had nothing to run): each card of it keeps that run's passes, the cards with the
# patch-id of each's change, for a batch formed again (batchkeep()), and which units each card selects (by): a unit
# its own passes (<worktree>.ready, still on its change) have, else, when none has it, each card with no own passes,
# else every card, as the run's combined change selected it.
batchpass() { # <card> <worktree> <units json> <cases> <the run's cards>
  local c=$1 wt=$2 u=$3 n=$4 m w x
  shift 4
  x=$(for m in "$@"; do w=$CARDS/$m; [ "$m" != "$c" ] || w=$wt
      jq -cn --arg c "$m" --arg p "$(bpid "$w")" --argjson r "$(jq -ce objects "$w.ready" 2>/dev/null || echo null)" '{card: $c, patch: $p, ready: $r}'; done \
    | jq -cs --argjson u "$u" --argjson n "$n" '
      def file: split("\t")[0];
      def meets($a; $b): ($a | file) == ($b | file) and ($a == $b or ($a | contains("\t") | not) or ($b | contains("\t") | not));
      [.[] | . as $m | {card, own: (.ready | if (type) == "object" and .tested == true and $m.patch != "" and .patch == $m.patch and (.units | type) == "array" then .units else null end)}] as $ms
      | [$u[] | . as $x | [$ms[] | select(any(.own[]?; meets(.; $x))) | .card] as $o
         | (if $o != [] then $o else [$ms[] | select(.own == null) | .card] | if . != [] then . else [$ms[].card] end end)[] | {card: ., unit: $x}] as $e
      | {cards: (map({(.card): .patch}) | add), units: $u, cases: $n,
         by: (reduce $ms[].card as $c ({}; .[$c] = [$e[] | select(.card == $c) | .unit]))}') || return 0
  for m in "$@"; do w=$CARDS/$m; [ "$m" != "$c" ] || w=$wt; printf '%s\n' "$x" > "$w.bpass"; done
}
# The batch's one test run, in the card's worktree: each card's patch on the ones before, in the batch's order. Which
# cards stay in it is found in that order, on main: a card whose patch does not apply on top of those kept before it,
# or whose product checks fail, leaves the batch: it waits on at its claim and is fitted afterwards, as any waiting card
# is. When that is the card's own patch, the card is apart (sets apart): the others are tested and land without it,
# then it is fitted onto main as they left it (card()); the batch returns 0, its own tests having passed. Should the card's own patch not apply in a run (a card it came after left), the batch is given up: the
# cards not yet judged wait on at their claims, and the card is tested alone. Red, the batch is split, no test left out: its
# first half, then its second on top of what passed, down to single cards. Each run is of the product checks on the
# change of the cards in it, then the tests; a check that fails is a red run. A second half whose first half passed whole
# is what just failed, so it is split with no run of its own (a single card is still run, for its output). A card red
# alone on top of what passed is the one that breaks it: a card it took is told its exit, given that run's output
# (<worktree>.test), and goes to its fix as if its own tests failed. Sets mates (the cards that passed, the card among
# them, in order; none when no other card passed); the card's worktree is left as it was, the output of the run that
# judged the card in <worktree>.test, and TEST_BATCH ({cases: 0, kept}: for the selected of its test line, when what
# judged it ran no case and kept that many passes; else empty, a run's log saying what it ran and kept).
# A run reuses each card's passed tests (the owner, 2026-11-13, issue #346; batchkeep()): it does not run a case a card
# passed on its own change, unchanged since (the same patch-id as in its <worktree>.ready), when no other card of the
# run selects it, nor a case the last batch run that passed passed for cards still in this one, on their unchanged
# changes. It runs the rest: the cases two or more cards select together, and every case of a card whose pass no
# longer holds. A run with none of those left runs nothing, and passes. Given up for it: two changes that each passed
# alone can fail together in a case only one of them selects; the whole test on main is the net.
batch() { # <card> <worktree> <the batch's cards, in order, the card among them>; returns the exit of the run that judged the card
  local c=$1 wt=$2 m s t out rc lrc=1 id half split=0 whole='' todo=() in=() good=() k=() lost='' bw='' br='' bf='' bz='' keep bt bb=''
  shift 2; mates=(); apart=''; TEST_BATCH=''
  # From here the worktree may hold the batch's changes, not the card's own: <worktree>.lent names the commit the
  # card's change (<worktree>.bpatch) goes on, for a card whose process is gone meanwhile (revive()); card() removes it.
  { git -C "$wt" diff --cached --binary --no-renames > "$wt.bpatch" && git -C "$wt" rev-parse HEAD > "$wt.lent"; } || { unbatch "$@"; tests "$wt"; return; }
  git -C "$wt" reset -q --hard || { unbatch "$@"; norun "$wt" "the card's worktree could not be cleared for its batch's tests"; return 1; }
  s=()
  for m in "$@"; do
    if [ "$m" = "$c" ]; then if git -C "$wt" apply --index "$wt.bpatch" 2>/dev/null; then s+=("$c"); else apart=1; fi
    elif git -C "$CARDS/$m" diff --cached --binary --no-renames > "$CARDS/$m.bpatch" 2>/dev/null && checks "$CARDS/$m" >/dev/null 2>&1 \
      && git -C "$wt" apply --index "$CARDS/$m.bpatch" 2>/dev/null; then s+=("$m"); else unbatch "$m"; fi
  done
  # Each part to run: "<the split it comes of> <0: first half, 1: second> <its cards>".
  todo=("0 0 ${s[*]}")
  while [ ${#todo[@]} != 0 ]; do
    read -r id half s <<<"${todo[0]}"; read -ra s <<<"$s"; todo=("${todo[@]:1}")
    git -C "$wt" reset -q --hard
    k=(); for m in "${good[@]}"; do if git -C "$wt" apply --index "$CARDS/$m.bpatch" 2>/dev/null; then k+=("$m"); elif [ "$m" = "$c" ]; then lost=1; else unbatch "$m"; fi; done; good=("${k[@]}")
    in=(); for m in "${s[@]}"; do if git -C "$wt" apply --index "$CARDS/$m.bpatch" 2>/dev/null; then in+=("$m"); elif [ "$m" = "$c" ]; then lost=1; else unbatch "$m"; fi; done
    if [ -n "$lost" ]; then
      unbatch "${good[@]}" "${s[@]}" $(for t in "${todo[@]}"; do echo "${t#* * }"; done)
      git -C "$wt" reset -q --hard && git -C "$wt" apply --index "$wt.bpatch" || { norun "$wt" "the card's change could not be put back in its worktree after its batch's tests"; return 1; }
      rm -rf "$wt.batchtest" "$wt.batchtestlog" "$wt.batchfirst"; echo "conveyor: card $c: its change no longer applied in its batch, so it is tested alone"; tests "$wt"; return
    fi
    [ ${#in[@]} != 0 ] || continue
    bt=''; TEST_REFUSED=''
    if [ "$half" = 1 ] && [ "$whole" = "$id" ] && [ ${#in[@]} = ${#s[@]} ] && [ ${#in[@]} -gt 1 ]; then rc=1
    else
      k=("${good[@]}" "${in[@]}"); echo "conveyor: card $c tests a batch of ${#k[@]}: ${k[*]}"
      t=$SECONDS
      if ! out=$(checks "$wt"); then rc=1; norun "$wt" "a product check failed on the change of ${k[*]}:"$'\n'"$out"
      # Every case the run would run passed on its cards' changes (batchkeep()): no run.
      elif keep=$(batchkeep "$c" "$wt" "${k[@]}") && jq -e .all <<<"$keep" >/dev/null; then
        rc=0; bt=$(jq -c '{cases: 0, kept}' <<<"$keep")
        norun "$wt" "no case to run: each passed on the change of the card that selects it, or in a batch run with each card that does: ${k[*]}"
        echo "conveyor: card $c: its batch of ${#k[@]} runs no case, each having passed on its cards' changes ($(jq .kept <<<"$keep") kept): ${k[*]}"
        batchpass "$c" "$wt" "$(jq -c .units <<<"$keep")" "$(jq .kept <<<"$keep")" "${k[@]}"
      else
        [ -z "$keep" ] || batchlist "$wt" "$keep"
        tests "$wt"; rc=$?
        [ $rc != 0 ] || [ ! -s "$wt.passed" ] || batchpass "$c" "$wt" "$(jq -c .units "$wt.passed")" "$(jq .cases "$wt.passed")" "${k[@]}"
      fi
      rm -f "$wt.passed"; t=$((SECONDS - t))
    fi
    whole=''; [ $rc != 0 ] || [ ${#in[@]} != ${#s[@]} ] || whole=$id
    if [ $rc != 0 ] && [ ${#in[@]} -gt 1 ]; then split=$((split + 1)); m=$((${#in[@]} / 2)); todo=("$split 0 ${in[*]:0:m}" "$split 1 ${in[*]:m}" "${todo[@]}"); continue; fi
    [ $rc != 0 ] || good+=("${in[@]}")
    for m in "${in[@]}"; do
      # The card's run's times go with its output (testrec()): a later part's run sets them again.
      if [ "$m" = "$c" ]; then lrc=$rc; keeprun "$wt" "$wt.batchtest" "$wt.batchtestlog" "$wt.batchfirst"; bw=$TEST_WAIT br=$TEST_RUN bf=$TEST_FREE bz=$TEST_REFUSED bb=$bt
      elif [ $rc != 0 ]; then
        keeprun "$wt" "$CARDS/$m.test" "$CARDS/$m.testlog" "$CARDS/$m.first" && jq -c --argjson r "$rc" --argjson s "$t" '. + {fail: $r, sec: $s}' "$CARDS/$m.batch" > "$CARDS/$m.batch.new" && mv -f "$CARDS/$m.batch.new" "$CARDS/$m.batch"
      fi
    done
  done
  git -C "$wt" reset -q --hard && git -C "$wt" apply --index "$wt.bpatch" || { unbatch "${good[@]}"; norun "$wt" "the card's change could not be put back in its worktree after its batch's tests"; return 1; }
  rm -f "$wt.first"; [ ! -e "$wt.batchtest" ] || { rm -rf "$wt.testlog"; mv -f "$wt.batchtest" "$wt.test"; [ ! -d "$wt.batchtestlog" ] || mv -f "$wt.batchtestlog" "$wt.testlog"; [ ! -e "$wt.batchfirst" ] || mv -f "$wt.batchfirst" "$wt.first"; TEST_WAIT=$bw TEST_RUN=$br TEST_FREE=$bf TEST_REFUSED=$bz TEST_BATCH=$bb; }
  [ ${#good[@]} -lt 2 ] && [ "${good[0]:-$c}" = "$c" ] || mates=("${good[@]}")
  [ -z "$apart" ] || return 0
  return $lrc
}

# A batch whose run passed while main moved (a card on other files landed during it) lands on that run, with no second
# one (owner, 2026-11-13: the batch holds the shared files through every run, so every card waiting on them waited for
# one more run of 5 to 10 minutes each time another card landed). Both must hold: no card of it has changed since the
# run (its staged change is the patch the run applied), and its changes still apply, in its order, to main as it is
# now. They are applied there in the card's worktree and the product checks run on the combined change (again, on
# main as it is then, each time main moves during them, so a card landing meanwhile costs no batch run): a check that
# fails is a red run of the batch, as in batch(): with the card and another card in it, the card's worktree is left on
# main as it is now with its change, mates the cards in it, and it returns 3 for card() to run the batch there
# (batch() splits it and sends the card that breaks it to its fix); else the batch is tested again, as when a card of
# it changed. So too when the cards landed during the run touch a test file the batch's change touches too
# (sharedtests()): it returns 3 as for a red run, or 1 when the card is alone in it or its change no longer applies,
# and its cards' passes are dropped, so the run again runs their tests. A card whose change no longer applies there leaves
# the batch and is fitted afterwards, as any waiting card is; the others land. When that is the card itself it is apart
# (sets apart), as in batch(). Sets mates to the cards that land. The card among them, its worktree is left on main as
# it is now with its change, where land() finds the batch's run. Else it is left there with no change, for the others'
# landing, and back names the commit the card's change goes back onto after it (card()). Returns 1 when the batch is
# to be tested again, the worktree as it was; 2 when the card's change could not be put back in its worktree; 3 for a
# red run (above).
rebatch() { # <card> <worktree>; card()'s mates is the batch
  local c=$1 wt=$2 m old new k=() left=() gone x w
  back=''
  old=$(git -C "$wt" rev-parse HEAD 2>/dev/null) && new=$(git rev-parse "refs/heads/$BRANCH" 2>/dev/null) || return 1
  [ "$old" != "$new" ] || return 0
  for m in "${mates[@]}"; do
    [ "$m" = "$c" ] || git -C "$CARDS/$m" diff --cached --binary --no-renames 2>/dev/null | cmp -s - "$CARDS/$m.bpatch" || return 1
  done
  # The worktree holds the batch fitted onto main from here: the card's change goes on old (<worktree>.lent, as in batch()).
  printf '%s\n' "$old" > "$wt.lent" || return 1
  asitwas() { git -C "$wt" reset -q --hard "$old" 2>/dev/null && git -C "$wt" apply --index "$wt.bpatch" 2>/dev/null; }
  while :; do
    k=() left=() gone=''
    git -C "$wt" reset -q --hard "$new" 2>/dev/null || { asitwas || return 2; return 1; }
    for m in "${mates[@]}"; do
      if [ "$m" = "$c" ]; then if git -C "$wt" apply --index "$wt.bpatch" 2>/dev/null; then k+=("$c"); else gone=1; fi
      elif git -C "$wt" apply --index "$CARDS/$m.bpatch" 2>/dev/null; then k+=("$m"); else left+=("$m"); fi
    done
    if [ ${#k[@]} = 0 ]; then asitwas || return 2
    else
      if ! m=$(checks "$wt"); then
        m=${m//$'\n'/ }
        if [ -z "$gone" ] && [ ${#k[@]} -gt 1 ]; then
          git -C "$wt" reset -q --hard 2>/dev/null && git -C "$wt" apply --index "$wt.bpatch" 2>/dev/null || { asitwas || return 2; return 1; }
          echo "conveyor: card $c: a product check failed on its batch's change on main as it is now, a red run, so the batch is run again there: ${m:0:300}"
          [ ${#left[@]} = 0 ] || unbatch "${left[@]}"
          mates=("${k[@]}"); return 3
        fi
        asitwas || return 2; echo "conveyor: card $c: a product check failed on its batch's change on main as it is now, so the batch is tested again: ${m:0:300}"; return 1
      fi
      # Main moved again during the checks: the batch is fitted onto main as it is now and they run there, not its tests.
      m=$(git rev-parse "refs/heads/$BRANCH" 2>/dev/null) && [ "$m" != "$new" ] && { new=$m; continue; }
      # The cards landed during the run touch a test file the batch touches too (sharedtests()): it is tested again,
      # keeping none of its cards' passes (<worktree>.ready's units, .bpass), which batchkeep() would else reuse.
      if m=$(sharedtests "$wt" "$old"); then
        for x in "${mates[@]}"; do w=$CARDS/$x; [ "$x" != "$c" ] || w=$wt; rm -f "$w.bpass"
          [ ! -e "$w.ready" ] || { jq -c 'del(.units, .cases)' "$w.ready" > "$w.ready.new" && mv -f "$w.ready.new" "$w.ready"; } || rm -f "$w.ready"; done
        m="conveyor: card $c: cards landed during its batch's run touch its test files too, so the batch is tested again: $(paste -sd ' ' <<<"$m")"
        if [ -z "$gone" ] && [ ${#k[@]} -gt 1 ]; then
          git -C "$wt" reset -q --hard 2>/dev/null && git -C "$wt" apply --index "$wt.bpatch" 2>/dev/null || { asitwas || return 2; return 1; }
          echo "$m on main as it is now"; [ ${#left[@]} = 0 ] || unbatch "${left[@]}"
          mates=("${k[@]}"); return 3
        fi
        asitwas || return 2; echo "$m"; return 1
      fi
      if [ -z "$gone" ] && [[ " ${mates[*]} " == *" $c "* ]]; then
        git -C "$wt" reset -q --hard 2>/dev/null && git -C "$wt" apply --index "$wt.bpatch" 2>/dev/null || { asitwas || return 2; return 1; }
      else git -C "$wt" reset -q --hard 2>/dev/null || { asitwas || return 2; return 1; }; back=$old; fi
      echo "conveyor: card $c: main moved during its batch's run, and the batch lands on that run: ${k[*]}"
    fi
    break
  done
  [ ${#left[@]} = 0 ] || unbatch "${left[@]}"
  [ -z "$gone" ] || apart=1
  # The card alone left of its batch lands alone, as a batch() of one does.
  [ ${#k[@]} -gt 1 ] || [ "${k[0]:-$c}" != "$c" ] || k=()
  mates=("${k[@]}")
}

# Under the lock, as one step: main gets one commit per card that is exactly its head plus the reviewed diff, then the
# landed lines are written. A diff that no longer applies is the rebase conflict; nothing is merged by hand. Prints the
# reason when it fails. A card an ordered card went past since its claim does not land (card() claims again first).
# A batch (batch(), above) is several cards landed in this one step, in the order given: each its own commit on the
# one before, with its own message, and its own landed line as if it landed alone, plus batch (the batch's cards, in
# order). Main moves once, to the last of them, so one push carries them all; a card that fails lands none of them.
# A card that waits in a batch is told its commit in <worktree>.batch.
#
# The lock orders Conveyor's own landings only; anything else may write main's checkout at any moment. So the commit
# is never made from that checkout: its tree is built in a private index, main's commit hooks judge that index and
# the message, and main moves by compare-and-swap from the head the tree was built on. The checkout gets the diff
# just before that, so a stop in between leaves it staged, never a head the checkout lags behind; a writer who
# edits the card's files meanwhile keeps that edit as their own uncommitted change. Nothing written to the checkout
# is ever taken back: once main has moved, another writer's commit may hold it, so the card is blocked for the owner.
# The branch is always named (refs/heads/<the pack's defaultBranch>), never HEAD: HEAD is whatever the checkout was last switched to.
PASSED="an ordered or ready card went past it since its claim; nothing was landed" # what land() prints for that: card() reads it
# What land() prints when main is not the commit the card's checks and tests ran on (its worktree's HEAD; for a card
# of a batch, the HEAD of the worktree of the card that took it, where the batch's run was, or where that run was found
# to stand since, rebatch()): card() fits the change onto main as it is now, and runs them again there when they do not
# stand. A change that does not apply to main, nor merge onto it three-way with no conflict left, is the rebase conflict
# first; one that merges so is only this (settle() fits it with the same merge).
STALE="main moved since its checks and tests ran; nothing was landed"
NOTWORK="the main checkout is not a working checkout (core.bare is true): set core.bare to false" # what land() prints for that
land() { # <card> <issue> <worktree> <commit message> [extra json for the landed line] [those five of each further card of a batch, in its order]
  local err sha l p base tip want x i h b='[]' a=("$@") g=() ls=() wts=() shas=() paths=()
  [ $# -le 5 ] || b=$(for ((i = 0; i < $#; i += 5)); do printf '%s\n' "${a[i]}"; done | jq -Rsc 'split("\n") | map(select(. != ""))')
  onmain() { [ "$(git symbolic-ref -q HEAD)" = "refs/heads/$BRANCH" ] || { echo "main's checkout is not on the $BRANCH branch; nothing was landed"; return 1; }; }
  # A checkout set to bare (core.bare=true) fails each git command that needs a work tree (status, diff, merge), so it is named as that, first (#254).
  [ "$(git rev-parse --is-inside-work-tree 2>/dev/null)" = true ] || { echo "$NOTWORK"; return 1; }
  onmain && base=$(git rev-parse "refs/heads/$BRANCH") || return 1
  tip=$base
  for ((i = 0; i < ${#a[@]}; i += 5)); do
    set -- "${a[@]:i:5}"; x=${5:-}; [ -n "$x" ] || x='{}'
    ! jq -e '.passed == true' "$3.claim" >/dev/null 2>&1 || { echo "$PASSED"; return 1; }
    # testedits: what it did to the test files main had (testedits(), lib/testfiles.sh), when it changed any.
    x=$(jq -c --argjson d "$(diffsize "$3")" --argjson e "$(ending)" --argjson b "$b" --argjson te "$(testedits "$3")" \
      '. + {diff: $d} + $e + (if $b == [] then {} else {batch: $b} end) + if $te == [] then {} else {testedits: $te} end' <<<"$x") \
      || { echo "cannot read the card's diff"; return 1; }
    git -C "$3" diff --cached --binary --no-renames > "$3.patch" && printf '%s\n' "$4" > "$3.msg" \
      && mapfile -d '' -O "${#paths[@]}" paths < <(git -C "$3" diff --cached --name-only --no-renames -z) || { echo "cannot read the card's diff"; return 1; }
    p=$(cardpatch "$3") # read before the private index is named: cardpatch() reads the worktree's own
    want=$(export GIT_INDEX_FILE="$3.index"; git read-tree "$tip" && fits "$3.patch" "$p" 2>&1 && git write-tree) \
      || { echo "rebase onto main conflicts: ${want:0:600}"; return 1; }
    want=${want##*$'\n'} # the tree id alone: what git apply printed on success (a new blank line at EOF, a clean three-way merge) comes first
    h=$3; [ ! -e "$3.batch" ] || h=$CARDS/$(jq -r .by "$3.batch" 2>/dev/null)
    [ "$(git -C "$h" rev-parse HEAD 2>/dev/null)" = "$base" ] || { echo "$STALE"; return 1; }
    # Exit 1 with nothing on stderr is a change; any other failure is git's own error, never read as a change.
    err=$(git diff --quiet "$base" -- "${paths[@]}" 2>&1); h=$?
    [ $h = 0 ] || { if [ $h = 1 ] && [ -z "$err" ]; then echo "main checkout has changes of its own to the card's files"
      else echo "cannot check main's checkout for changes of its own: git diff failed (exit $h): ${err:0:600}"; fi; return 1; }
    # A later card of a batch is judged on the commit before it: HEAD is that commit (a checkout-less worktree's own
    # HEAD), main's checkout its files, so its hooks see its own change alone, as if it landed alone.
    g=(); [ "$tip" = "$base" ] || { git worktree remove --force "$3.head" 2>/dev/null; git worktree add -q --detach --no-checkout "$3.head" "$tip" 2>/dev/null \
      && g=("GIT_DIR=$(git -C "$3.head" rev-parse --absolute-git-dir)" "GIT_WORK_TREE=$MAIN"); } || { echo "cannot make the commit before the card's to judge it on"; return 1; }
    err=$(export GIT_INDEX_FILE="$3.index" "${g[@]}"; git hook run --ignore-missing pre-commit 2>&1 && git hook run --ignore-missing commit-msg -- "$3.msg" 2>&1); h=$?
    [ "$tip" = "$base" ] || git worktree remove --force "$3.head" 2>/dev/null
    [ $h = 0 ] || { echo "commit refused: ${err:0:600}"; return 1; }
    [ "$(GIT_INDEX_FILE="$3.index" git write-tree)" = "$want" ] || { echo "main's hooks changed what would be committed: it is not exactly the reviewed diff; it needs $OWNER"; return 1; }
    sha=$(git commit-tree "$want" -p "$tip" -F "$3.msg") || { echo "cannot make the commit object"; return 1; }
    p=false; ! product "$sha" || p=true
    ls+=("$(jq -c --arg s "$sha" --argjson p "$p" '. + {sha: $s, product: $p}' <<<"$x")"); wts+=("$3"); shas+=("$sha"); tip=$sha
  done
  onmain && [ "$(git rev-parse "refs/heads/$BRANCH")" = "$base" ] || { echo "main moved during the landing; nothing was landed"; return 1; }
  # The checkout gets every card's change in one apply, which writes all or nothing: a change that no longer applies
  # leaves none of the batch's behind.
  err=$(git diff --binary --no-renames "$base" "$tip" | git apply --index 2>&1) || { echo "rebase onto main conflicts: ${err:0:600}"; return 1; }
  git update-ref -m "conveyor ${a[0]}" "refs/heads/$BRANCH" "$tip" "$base" \
    || { echo "main moved during the landing; nothing was landed, and the card's change is left in main's checkout for $OWNER to sort out"; return 1; }
  for i in "${!wts[@]}"; do
    l=$(line "${a[i * 5]}" "${a[i * 5 + 1]}" landed ok "${ls[i]}") && append "$l" || { echo "landed as ${shas[i]} but the record line failed"; return 1; }
    [ ! -e "${wts[i]}.batch" ] || { jq -c --arg s "${shas[i]}" '. + {landed: $s}' "${wts[i]}.batch" > "${wts[i]}.batch.new" && mv -f "${wts[i]}.batch.new" "${wts[i]}.batch"; }
  done
}
