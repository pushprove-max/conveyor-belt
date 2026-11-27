# SPDX-License-Identifier: Apache-2.0
# Same-file cards. Two cards in flight that changed the same file found out only at landing,
# where the second one's change no longer applied. Cards review in parallel; each claims the files its staged change
# names after its review, before it lands, in <worktree>.claim: {pid: the card's process, paths, held, passed: an ordered card went
# past it since, was: passed as it stood when this claim was granted, turn: it waits on the card that has the landing
# turn, turnq()}, the change itself beside it (<worktree>.cpatch).
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
# back at its claim (back), unless it gave way to wait for main to change (red). Back there and waiting, it waits too
# for the cards it gave way to (for) that are ready and have not yet claimed the files, and stays away. Its claims keep its count of give-ways (gave). The card that
# claims the files of one that gave way is named on it (to: its issue), for the Board and its live record (watch()).
# A card a batch took (<worktree>.batch: by) waits on the card whose batch it is, which holds its files (gather()),
# even when it became ready first: going past that card would make land() refuse the batch (PASSED).
# The lists of files and the claims go to jq by file, never as arguments: one argument over 128 KiB fails to start jq on Linux.
# The order orderfix() fixed: while the card it lands after (its claim's after, af) has a live claim on a file of this
# one, and has not given way (giveway(): away; back at its claim it has its turn again), it waits on that card, whatever
# the other rules say (a batch that took it aside). A card away is left to the other rules, as before; when they too
# make it wait on that card, its claim keeps naming the card it lands after. It never waits on a card whose after leads
# back to it (leads()), or the two would wait on each other.
claim() { # <card> <worktree> <the card's pid>; under the lock
  local mine others raw o c w ord cl away af for='[]' apart='[]' notready=0 unready='' stk t ms=null rdy='' kh kn mr r
  { cl=$(<"$2.claim"); } 2>/dev/null || cl=''; ord=$(ctl 2>/dev/null) || ord='{"order": []}' # the control record whole: the jq below reads its order (#595)
  # From one jq (#595): its change's files, its claim's give-way (away; none when it did not give way), what claimline() keeps of it (kh held, kn not) and af.
  t=$(git -C "$2" diff --cached --name-only --no-renames -z | jq -rRsc --rawfile cl <(printf '%s' "$cl") '(split("\u0000") | map(select(. != "" and (endswith(".md") | not)))),
    (([$cl | try fromjson catch null | objects] | first // {}) as $c | ($c.passed == true) as $was | ($was and $c.fit == true) as $f | ([$c.gave // 0 | numbers] | first // 0) as $g
      | ({gave: $g, was: ($was and ($f | not))} | tojson | .[1:-1]), ({gave: $g, passed: $was} + (if $f then {fit: true} else {} end) | tojson | .[1:-1]), ([$c | select(.away == true) | {away, for: (.for // [] | arrays), to: (.to // null), fixing: (.fixing == true)}] | first // ""), ([$c | select(.held != true) | .after | strings | select(test("^[A-Za-z0-9._-]+$"))] | first // ""))') || return 1
  { IFS= read -r mine; IFS= read -r kh; IFS= read -r kn; IFS= read -r away; IFS= read -r af; } <<<"$t"; [ -n "$away" ] || away='{"for": []}'
  # This runs every turn of a wait (settle()), so it starts no program whose answer is known (#532): a card not away
  # waits for no card it gave way to (for), and with no other card's live claim nothing below changes what it waits on.
  [ "$away" = '{"for": []}' ] \
    || for=$(for o in $(jq -r '.for[]' <<<"$away"); do [ ! -d "$CARDS/$o" ] || ! ready "$CARDS/$o" || printf '%s\n' "$o"; done | jq -Rsc 'split("\n") | map(select(. != ""))')
  # Each live claim, the card's own pid read with it: "<pid> <claim>". Not of a card stacked on this one (its worktree on
  # the stack's base, stackto()): it lands after this one, so this one never waits on it.
  others=$(for o in "$CARDS"/*.claim; do
      [ -e "$o" ] && [ "$o" != "$2.claim" ] || continue
      c=${o##*/}
      [ ! -e "${o%.claim}.stack" ] || ! jq -e --arg me "$1" --arg h "$(git -C "${o%.claim}" rev-parse HEAD 2>/dev/null)" '.on == $me and .base == $h' "${o%.claim}.stack" >/dev/null 2>&1 || continue
      o=$(jq -r --arg c "${c%.claim}" 'select((.pid | type) == "number" and (.paths | type) == "array") | "\(.pid) \(. + {card: $c} | tojson)"' "$o" 2>/dev/null) || continue
      [ -z "$o" ] || ! kill -0 "${o%% *}" 2>/dev/null || printf '%s\n' "${o#* }"
    done) || return 1
  others="[${others//$'\n'/,}]"; raw=$others # one claim a line, each one line of JSON (tojson): no jq makes the list (#1542); raw: away ones too, for af
  # Cards whose change applies together with this one are no overlap: left out here, as if they shared no file.
  git -C "$2" diff --cached --binary --no-renames > "$2.cpatch.new" || return 1
  if [ "$others" != '[]' ]; then
    apart=$(together "$2.cpatch.new" "$mine" "$others" "$(cardpatch "$2" ':(exclude)*.md')") || return 1
    # A card stacked on another (its worktree on the stack's base, stackto()): its change applies on that card's, and
    # it lands only after it, so it waits on it still; but not on that card away for a fix round (giveway()): for the
    # fix of its failed tests (fixing), or, once its own tests passed on the change it holds (testedhere()), for the
    # fix of its review's findings (fix; the owner, 2026-11-17). It is fitted onto main alone then, and lands.
    stk=''; [ ! -e "$2.stack" ] || stk=$(jq -r --arg h "$(git -C "$2" rev-parse HEAD 2>/dev/null)" 'select(.base == $h) | .on' "$2.stack" 2>/dev/null) || stk=''
    if [ -n "$stk" ]; then
      t=false; ! jq -e --arg s "$stk" 'any(.[]; .card == $s and .away == true and .fix == true)' <<<"$others" >/dev/null || ! testedhere "$2" || t=true
      apart=$(jq -c --arg s "$stk" 'map(select(. != $s))' <<<"$apart") \
        && others=$(jq -c --arg s "$stk" --argjson t "$t" 'map(select(.card != $s or .away != true or (.fixing != true and (.fix != true or ($t | not)))))' <<<"$others") || return 1
    fi
    ready "$2" || notready=1
    # One jq (#595) for the three steps, its first line: the cards whose change applies with this one left out; then,
    # when this card is not ready and a card away (not back, nor red: waiting for main, which the main-red fix card
    # changes) shares its files, each such card held, the others away left out; else every card away left out. Then each card left that shares its files, "<held> <card>".
    # Ready, it does not wait behind a waiting card that shares its files and is not ready (it may wait on a card away):
    # unready, one a line. When the tests of each passed (rdy: "<card>\t<since>" lines, readysince()), for which goes first.
    # It makes readysince()'s read of each <worktree>.ready too (readyrows(), #595): its 2nd line this card's, then each.
    { IFS= read -r others && IFS= read -r mr && while IFS=$'\x1f' read -r t o r; do
        [ $notready = 1 ] || [ "$t" = true ] || [ ! -d "$CARDS/$o" ] || ready "$CARDS/$o" || unready+=$o$'\n'
        ! t=$(readysince "$CARDS/$o" "$r") || rdy+=$o$'\t'$t$'\n'
      done; } < <(jq -rc --argjson a "$apart" --slurpfile m <(printf '%s' "$mine") --argjson n "$notready" --rawfile rd <(readyrows "$2") '$m[0] as $m
      | ($rd | split("\n") | map(select(. != "") | index("\t") as $i | {key: .[:$i], value: .[$i + 1:]}) | from_entries) as $rd
      | def rs($c): [$rd[$c] // "" | try fromjson catch null | objects | select(.tested == true and (.since | type) == "number") | "\(.patch | strings // "")\t\(.since)"] | first // "";
      map(select(.card | IN($a[]) | not))
      | if $n == 1 and any(.[]; .away == true and .back != true and .red != true and (.paths - (.paths - $m)) != []) then map(if .away != true then . elif .back != true and .red != true then .held = true else empty end)
        else map(select(.away != true)) end
      | ., rs(""), (.[] | select((.paths - (.paths - $m)) != []) | "\(.held == true)\u001f\(.card)\u001f\(rs(.card))")' <<<"$others")
    [ -n "$others" ] || return 1
    # When its own tests passed (ms, readysince(); null when they have not or its change no longer fits main).
    [ $notready = 1 ] || ms=$(readysince "$2" "$mr") || ms=null
  fi
  w=$(stdb ask lines cards | jq -cn --slurpfile mine <(printf '%s' "$mine") --slurpfile o <(printf '%s' "$others") --arg me "$1" --argjson ord "$ord" --argjson for "$for" --arg un "$unready" --argjson ms "$ms" --arg rdy "$rdy" --arg bt "$(cat "$2.batch" 2>/dev/null)" --arg af "$af" --slurpfile raw <(printf '%s' "$raw") --argjson ap "$apart" \
      '$mine[0] as $mine | $o[0] as $o | $raw[0] as $raw | ($un | split("\n") | map(select(. != ""))) as $un
      | ([$bt | try fromjson catch null | objects | .by // empty | if type == "string" then . else tojson end] | first // "") as $by | ($rdy | split("\n") | map(select(. != "") | split("\t") | {(.[0]): (.[1] | tonumber)}) | add // {}) as $rdy
      | $ord.order as $ord | [inputs] as $all | [$all[] | select(.step == "picked")] as $p | ($p | map(.card)) as $order | ($ord | length) as $n
      | [$all[] | select(.step | IN("landed", "closed", "blocked")) | .card] as $ended
      | def at($c): $order | index($c) // -1;
        def rank($c): ($p | map(select(.card == $c)) | first | .issue) as $i | ($ord | index($i)) // $n;
        def rs($c): if $c == $me then $ms else $rdy[$c] end;
        def key($c): [rank($c), (rs($c) == null), (rs($c) // 0), at($c)];
      rank($me) as $r
      # A holder it goes past as a ready card (fit): of its rank, its tests not passed, or passed after its own.
      | def fit($c): $ms != null and rank($c) == $r and key($c) > key($me);
        def leads($c; $k): ([$raw[] | select(.card == $c) | .after | strings] | first) as $a | $a != null and $k < 100 and ($a == $me or leads($a; $k + 1));
      ([$raw[] | select($af != "" and .card == $af and (.away != true or .back == true) and at(.card) >= 0 and (.card | IN($ended[]) | not) and (.card | IN($ap[]) | not)) | . + {shared: (.paths - (.paths - $mine))} | select(.shared != [])] | first) as $aw
      | [$o[] | select(at(.card) >= 0 and (.card | IN($ended[]) | not) and (leads(.card; 0) | not)) | . + {shared: (.paths - (.paths - $mine))} | select(.shared != [])] as $s
      | ([$s[] | select(.card == $by or if .held == true then ($r == $n or rank(.card) < $n) and (fit(.card) | not) else key(.card) < key($me) and (rank(.card) < $r or (.card | IN($un[]) | not)) or (.card | IN($for[])) and rank(.card) <= $r end)]
        | min_by(key(.card))) as $w
      | if $by == "" and $aw then {on: $aw.card, paths: $aw.shared, after: $aw.card} elif $w then {on: $w.card, paths: $w.shared} + (if $w.card == $af then {after: $af} else {} end) else {past: [$s[] | select(.held == true and (fit(.card) | not)) | .card], fit: [$s[] | select(.held == true and fit(.card)) | .card]} end') || return 1
  # w is {"on":…} (the card it waits on) or {"past":[…],"fit":[…]} (the cards it went past, as an ordered card and as
  # a ready one), as jq -c prints them. One an ordered card went past is reviewed again (was, settle()); one only ready
  # cards went past is marked fit, and is not. A ready card let go on has the landing turn, or waits on it (turnq()).
  case $w in '{"on":'*) ;; *) t=$(turnq "$1" "$2" "$3") || return 1; [ -z "$t" ] || w=$t ;; esac
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
  claimline "$3" "$mine" "$w" "$kh" "$kn" "$away" > "$2.claim.new" && mv -f "$2.cpatch.new" "$2.cpatch" && mv -f "$2.claim.new" "$2.claim" || return 1
  if [ -z "$w" ] && [[ ${1##*-} =~ ^[0-9]+$ ]]; then
    for o in "$CARDS"/*.claim; do
      c=${o##*/}
      [ -e "$o" ] && [ "$o" != "$2.claim" ] && { [ "$apart" = '[]' ] || ! jq -e --arg c "${c%.claim}" 'index($c)' <<<"$apart" >/dev/null; } || continue
      { jq -e --slurpfile m <(printf '%s' "$mine") '$m[0] as $m | .away == true and .to == null and (.paths | type) == "array" and (.paths - (.paths - $m)) != []' "$o" >/dev/null \
        && jq -c --argjson to $((10#${1##*-})) '.to = $to' "$o" > "$o.new" && mv -f "$o.new" "$o"; } 2>/dev/null || :
    done
  fi
  printf '%s' "$w"
}
# claim()'s lines of the <worktree>.ready files, for its jq (rs()), with no jq (#595: claim() runs each turn of a wait):
# "<card>\t<the file, its line ends as spaces>", the one at <worktree> with no card. JSON has no raw tab or line end in
# a string.
readyrows() { # <worktree>
  local o r c
  for o in "$1.ready" "$CARDS"/*.ready; do
    r=''; { IFS= read -r -d '' r < "$o"; } 2>/dev/null || [ -n "$r" ] || continue
    c=${o##*/}; [ "$o" != "$1.ready" ] || c=''; printf '%s\t%s\n' "${c%.ready}" "${r//$'\n'/ }"
  done
}
# claim()'s claim, one line of JSON as jq -c writes it, with no jq (#595: claim() runs each turn of a wait): its pid,
# files and held, then what it keeps of the claim before it (claim()'s kh when held, kn when not: whether it was
# passed, as a ready card only, and its gave). Not held: the card it waits on (on, for orderfix()), turn when it waits on
# the card with the landing turn, the card it lands after when orderfix() fixed its turn (after), and its give-way
# (claim()'s away), back. The wait's card ids are read from where jq -c puts them: on first, after last.
claimline() { # <pid> <paths json> <claim()'s wait: empty when held> <kh> <kn> <away>
  local t
  [[ $1 =~ ^[1-9][0-9]*$ ]] || return 1
  if [ -z "$3" ]; then printf '{"pid":%s,"paths":%s,"held":true,%s}\n' "$1" "$2" "$4"; return; fi
  t="{\"pid\":$1,\"paths\":$2,\"held\":false,$5"; [[ $3 != *'"turn":true'* ]] || t+=',"turn":true'
  [[ ! $3 =~ ^\{\"on\":\"([A-Za-z0-9._-]+)\" ]] || t+=",\"on\":\"${BASH_REMATCH[1]}\""
  [[ ! $3 =~ ,\"after\":\"([A-Za-z0-9._-]+)\"\}$ ]] || t+=",\"after\":\"${BASH_REMATCH[1]}\""
  [ "$6" = '{"for": []}' ] || t+=",${6:1:-1},\"back\":true"
  printf '%s}\n' "$t"
}

# Whether <patch> fits onto the index GIT_INDEX_FILE names, and puts it there: applied as it is, or, where that fails, a
# three-way merge that leaves no conflict and the same change, its own added and removed lines being <id> (cardpatch()).
# A merge that leaves another change does not fit: a change main holds already merges to nothing. The git apply options
# go to both tries. What git apply prints of the merge goes to stderr. The patch is named by its absolute path.
fits() { # <patch> <id> [git apply option...]
  local t
  git apply --cached "${@:3}" "$1" 2>/dev/null && return 0
  t=$(git write-tree) && merge3 "${@:3}" "$1" || return 1
  [ -n "$2" ] && { t=$(git diff --cached --binary --no-renames -U0 "$t" | diffid); [ "$t" = "$2" ]; } \
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
  local d o l=''
  d=$(mktemp -d) || return 1
  if GIT_INDEX_FILE=$d/main git read-tree "refs/heads/$BRANCH" 2>/dev/null; then
    for o in $(jq -r --slurpfile m <(printf '%s' "$2") '$m[0] as $m | .[] | select((.paths - (.paths - $m)) != []) | .card' <<<"$3"); do
      [ -e "$CARDS/$o.cpatch" ] && cp "$d/main" "$d/index" && GIT_INDEX_FILE=$d/index merge3 --exclude='*.md' "$CARDS/$o.cpatch" >/dev/null 2>&1 \
        && GIT_INDEX_FILE=$d/index fits "$1" "$4" --exclude='*.md' >/dev/null 2>&1 && l+=$o$'\n'
    done
  fi
  # None, as at most turns of a wait (claim()): the empty list with no jq (#595).
  if [ -z "$l" ]; then echo '[]'; else jq -Rsc 'split("\n") | map(select(. != ""))' <<<"$l"; fi
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
# fix of the card's failed tests, for the Board; fix one for the fix of its review's findings. red gives way to wait for
# main to change while main is red (cardland.sh mainredhold(), cardfailed()): not capped, as the card cannot land until
# main changes and the main-red fix card may need its files: a claim kept then has both wait for good. Its claim is
# marked red until it is back, so a card that is not ready does not wait for it either (claim()).
GIVEWAY=3
giveway() { # <card> <worktree> [fixing|fix|red]; under the lock
  local o f='[]' s=false
  [ "${3:-}" != red ] || s=true
  # Gone back for a fit, a review, a fix or a run again, it lands next no more: its landing turn ends (turnon()).
  turnfree "$1"
  # A claim already away (given way to be fitted, reviewed or fixed: no settle() since) is marked red for the wait too.
  if [ "$s" = true ] && jq -e '.away == true' "$2.claim" >/dev/null 2>&1; then
    jq -c '.red = true' "$2.claim" > "$2.claim.new" && mv -f "$2.claim.new" "$2.claim"; return 1
  fi
  # A card stacked on this one (stackto()) goes on once this one gives way for a fix round (claim()): that give-way is
  # not capped, and a claim already away (given way to be fitted, reviewed or tested again) is marked for that round.
  if [ "${3:-red}" != red ] && jq -e --arg c "$1" 'select(.on == $c)' "$CARDS"/*.stack >/dev/null 2>&1; then
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
  jq -c --argjson f "$f" --arg x "${3:-}" '{pid, paths, held: false, away: true, gave: ((.gave // 0) + 1), for: $f, to: null, fixing: ($x == "fixing"), fix: ($x == "fix"), red: ($x == "red")}' "$2.claim" > "$2.claim.new" && mv -f "$2.claim.new" "$2.claim"
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
  # This runs at each turn of a wait (settle()): H, when the issue names H's in no `Depends on:` line, from one jq (#1542).
  # The same jq says whether the card and H are at different places in the control record's order list (o), for an H
  # whose tests have not passed (#595: no jq of its own).
  o=$(ctl 2>/dev/null) || o=null
  h=$(jq -r --slurpfile w <(printf '%s' "$3") --slurpfile o <(printf '%s' "${o:-null}") --arg me "${1##*-}" "$DEPS"'. as $i | $w[0].on | strings | select(test("-[0-9]+$")) | select((sub(".*-"; "") | tonumber) as $h | $i | needs | index($h) | not)
    | "\(.)\t\(($o[0] | (.order | arrays) // []) as $ord | (try ($me | tonumber) catch null) as $a | (sub(".*-"; "") | tonumber) as $b | ($ord | index($a) // -1) != ($ord | index($b) // -1))"' <<<"$4" 2>/dev/null) \
    && [ -n "$h" ] && [[ ${1##*-} =~ ^[0-9]+$ ]] && packget landBatch n && [ "$n" -gt 1 ] || return 1
  o=${h#*$'\t'} h=${h%%$'\t'*}
  [ "$o" = true ] || readysince "$CARDS/$h" >/dev/null || return 1
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

# The lap of a wait at a claim (settle()) since its last look, noted for the card's records (waitnote(),
# lib/records.sh): <worktree>.waitlap holds the wait's name and the time of that look (epoch seconds). Each call notes
# the seconds since then under that name, then starts the next lap from now under <name>, or with no name ends the
# wait. With no lap open it notes nothing and starts none, unless new is given: then it starts one and notes no lap
# it finds. It runs under the lock (locked), as landone() does, which ends the lap of each card its batch lands as it
# writes the card's landed line: a batch that lands a card while it sleeps between two looks puts that lap on the
# landed line, never on a later line of the card.
waitlap() { # <card> <worktree> [name] [new]
  local n t
  # 2>/dev/null before the read's < (redirects go left to right): a card with no lap open yet (its first wait) printed
  # "No such file or directory" on stderr.
  if read -r n t 2>/dev/null < "$2.waitlap" && [ -z "${4:-}" ]; then
    [[ ! $t =~ ^[0-9]+$ ]] || [ $((EPOCHSECONDS - t)) -le 0 ] || waitnote "$1" "$n" "$((EPOCHSECONDS - t))" || :
  elif [ -z "${4:-}" ]; then return 0; fi
  if [ -n "${3:-}" ]; then printf '%s %s\n' "$3" "$EPOCHSECONDS" > "$2.waitlap"; else rm -f "$2.waitlap"; fi
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
settle() { # <card> <issue> <worktree> <the sessions' prompt> <step it waits to begin> <issue json>; sets card()'s caught, trc, sec, waitsec, behind and parsecheck; reads its ph
  local me=$BASHPID w waited='' ws wb wn='' wo old err t moved=0 away b bl bf bt bs bp out id mt cf tf ix docs dp onto stk rd rt
  ! jq -e '.away == true and (.to | type) == "number"' "$3.claim" >/dev/null 2>&1 || caught=''
  rm -f "$3.waitlap" # a lap an earlier call left open is no wait of this one
  while :; do
    # In a wait, what the card has waited is brought up to date each time round, the last one of the wait too: a wait
    # that ends between two looks counts whole. A ready card's <worktree>.ready carries it too (extra.waitSec, with
    # card()'s mainsec): a batch that lands it writes its landed line from that extra (fives()), for the drift watch.
    # Its card records note the seconds since the last look (waitlap()), as wn names the wait of that look: turn,
    # queued behind the card with the landing turn (turnq()), else cards.
    if [ -n "$waited" ]; then
      waitsec=$((wb + SECONDS - ws))
      readyput "$3" '.extra.waitSec = $w' --argjson w "$((waitsec + ${mainsec:-0}))" || :
      locked waitlap "$1" "$3" "$wn" || :
    fi
    # A change a session changed here is reviewed again before it lands: no batch takes it till then (gather()).
    [ $moved = 0 ] || rm -f "$3.ready"
    # The card records kept in this shell (stdb, lib/records.sh): a look that finds them unchanged asks no database.
    stdb ask lines cards >/dev/null 2>&1 || :
    w=$(locked claim "$1" "$3" "$me") || { rm -f "$3.idle"; block "$1" "$2" "$3" "$5: the engine could not write the claim on the files of the card"; return 1; }
    # While it only sleeps out a wait, on a card or on the batch card that took it, <worktree>.idle stands: the machine's
    # count (room()) leaves the card out then, as idle() (lib/run.sh) counts it; the card cap counts it. It goes before
    # any work of the card, and so does the <worktree>.nocap mark of the land step: its lint, checks and tests run
    # before the landing, so the loop counts the card against the cap then (capmark(), lib/run.sh).
    # Taken into a batch (gather()): it waits for the card that took it, which lands it (3) or finds it breaks the
    # batch's tests (4). A batch whose card is gone takes it no more.
    if [ -e "$3.batch" ]; then
      # Its fields from one read (#595): whether landed and fail are set, fail's value, sec and pid; none set and pid 0
      # when it is not one JSON object.
      IFS=$'\x1f' read -r bl bf bt bs bp < <(jq -r 'objects | [(.landed | . != null and . != false), (.fail | . != null and . != false), (.fail | tostring), (.sec // 0 | tostring), (.pid // 0 | tostring)] | join("\u001f")' "$3.batch" 2>/dev/null) \
        || { bl=false bf=false bp=0; }
      [ "$bl" != true ] || { rm -f "$3.idle"; return 3; }
      # That run was the batch card's: its wait and run are not known here (testrec()).
      [ "$bf" != true ] || { trc=$bt; sec=$bs; TEST_WAIT=''; TEST_RUN=''; TEST_FREE=''; rm -f "$3.batch" "$3.idle"; locked waitlap "$1" "$3" || :; capowed "$1" "$2" "$3" "$5"; return 4; }
      if kill -0 "$bp" 2>/dev/null; then [ -n "$w" ] || { : > "$3.idle"; sleep "$LIVE"; continue; }; else rm -f "$3.batch"; fi
    fi
    # Told to wait, it is stacked on that card instead when it can be (stackto()): fitted below onto the stack's base
    # (onto), not main, and reviewed there; not while a batch holds it, nor on the card that has the landing turn
    # (turnq(): they share no file, and the next batch takes it).
    stk=''
    if [ -n "$w" ] && [[ $w != *'"turn":true'* ]] && [ ! -e "$3.batch" ] && onto=$(stackto "$1" "$3" "$w" "$6"); then
      stk=$(jq -r .on <<<"$w"); w=''; echo "conveyor: card $1 is stacked on card $stk, which changes the same files: it is fitted onto main with that card's change"
    else onto=refs/heads/$BRANCH; fi
    if [ -n "$w" ]; then
      # Each wait begins with its start line, one after a session of this call too (a card that kept its claim through
      # the session that brought it onto main): `health` counts a wait whose start line is the card's last.
      # A card that waits on another card cannot land next: its landing turn ends (turnon()), or the two would wait
      # on each other.
      wo=$wn; wn=cards; [[ $w != *'"turn":true'* ]] || wn=turn
      [ -z "$waited" ] || [ "$wn" = "$wo" ] || locked waitlap "$1" "$3" "$wn" || :
      [ -n "$waited" ] || { waited=$(date -u +%FT%TZ); ws=$SECONDS; locked waitlap "$1" "$3" "$wn" new || :; wb=$waitsec; locked turnfree "$1"
        began "$1" "$2" "$5"; jq -r --arg c "$1" 'if .turn then "conveyor: card \($c) is queued for the next batch: card \(.on) has the landing turn"
          else "conveyor: card \($c) waits on card \(.on), which changes the same files: \(.paths | join(", "))" end' <<<"$w"; }
      # The live record names the card it waits on now: one `retry` gives back is picked first, past the cap (urgent).
      # It names too (waited) what the card waited before this wait (before: the seconds of its waits that ended) and
      # every card it has waited on, in order (behind), so `health` can say when all its waits together pass WAIT_LIMIT.
      # One jq for both (#595): the list on its first line, then the live record; a list that does not read is none. Its
      # third line says whether <worktree>.ready marks it tested, alone or stackred (rt: true or false; none when that
      # jq did not run, and then its checks and tests do not run this turn).
      rd=''; { rd=$(<"$3.ready"); } 2>/dev/null
      t='' rt=''; { IFS= read -r behind && IFS= read -r t && IFS= read -r rt; } < <(jq -cn --slurpfile wf <(printf '%s' "$w") --arg at "$waited" --arg s "$5" --argjson wb "$wb" --arg bh "$behind" --rawfile rd <(printf '%s' "$rd") '
        $wf[0] as $w | ([$bh | try fromjson catch null | arrays] | first // [] | if index($w.on) then . else . + [$w.on] end) as $bh
        | $bh, {step: $s, at: $at, last: (now | todate), turns: 0, waits: ($w | {on, paths}), waited: {before: $wb, behind: $bh},
        action: (if $w.turn then "queued for the next batch: card \($w.on) has the landing turn" else "waiting on card \($w.on), which changes the same files: \($w.paths | join(", "))" end)},
        ([$rd | try fromjson catch null | try (.tested == true or .alone == true or .stackred == true) catch false] | first // false)' 2>/dev/null) || behind='[]'
      [ -z "$t" ] || { printf '%s\n' "$t" > "$3.live.tmp" && mv -f "$3.live.tmp" "$3.live"; } 2>/dev/null
      # Waiting after a GO (<worktree>.ready), with batches on, it runs its own product checks and changed tests,
      # holding nothing: only a card whose own tests passed is ready, so no batch lands a card that fails alone. Its
      # checks failing block it, as at its turn; its tests failing send it to its fix (4). Not one merged onto main
      # whose files have not been found to parse (parses()): that check runs first, at its turn (card()). A stacked card
      # (stackto()) is checked here, so it is tested on its base while it waits. On its base, its checks or tests that
      # fail may fail for that card's change, which has not passed its own yet: it is not blocked or fixed for that, but
      # marked (stackred) and waits on, untested; it runs them again where it goes next (fitted onto main once that card
      # landed or failed its tests).
      [ -z "$parsecheck" ] || [ ! -e "$3.stack" ] || ! parses "$3" >/dev/null 2>&1 || parsecheck=''
      # Not while main is red at its commit, nor while its worktree is on a commit the main-red record holds an entry for
      # (mainred.sh redhere()): main may have moved past that commit while the card waited, and the run would fail there on
      # the old failure, before the fit onto main below. As in its test step (cardland.sh mainredhold()), it waits on.
      if [ -z "$parsecheck" ] && [ -e "$3.ready" ] && [ "$rt" = false ] && packget landBatch b && [ "$b" -gt 1 ] \
        && ! redhere "$1" >/dev/null && ! redhere "$1" "$3" >/dev/null; then
        # Its wait so far may have lent its slot under the cap to a held card (capowed(), lib/cardland.sh). The seconds
        # of that wait for room, and of the checks and tests below, are not noted as its wait on cards: a new lap starts.
        rm -f "$3.idle" "$3.nocap"; capowed "$1" "$2" "$3" "$5"; locked waitlap "$1" "$3" "$wn" new || :
        # The gate for a waiting card first (lintwait(), lib/lint.sh): a finding or an execution error removes
        # <worktree>.ready, so it waits on with no check, test or session, and its landing gate deals with it. Its lint
        # line goes after the wait's start line: a new start line makes the wait the card's last step again, so the
        # Board and `health` see the wait and its time limit. The persisted-contract check (contractwait(),
        # lib/contract.sh) after it, the same way: a batch lands a card with no turn at its landing gate. Then its push
        # checks (pushgatewait(), lib/contract.sh), the same way.
        { lintwait "$1" "$2" "$3" && contractwait "$1" "$3" && pushgatewait "$1" "$3"; } || { began "$1" "$2" "$5"; : > "$3.idle"; sleep "$LIVE"; continue; }
        sec=$SECONDS; trc=''
        if ! out=$(checks "$3"); then
          trc=1; [ "$(git -C "$3" rev-parse HEAD 2>/dev/null)" = "$(jq -r .base "$3.stack" 2>/dev/null)" ] || { block "$1" "$2" "$3" "a product check failed; nothing landed."$'\n'"$out"; return 1; }
        else began "$1" "$2" test; tests "$3"; trc=$?; fi
        sec=$((SECONDS - sec)); locked waitlap "$1" "$3" "$wn" new || :
        # Its run did not run or was stopped (tests(): <worktree>.stop): blocked
        # with that reason, as at its turn (card()).
        [ "$trc" = 0 ] || [ ! -s "$3.stop" ] || { block "$1" "$2" "$3" "test: $(<"$3.stop")"; return 1; }
        if [ "$trc" != 0 ] && [ "$(git -C "$3" rev-parse HEAD 2>/dev/null)" = "$(jq -r .base "$3.stack" 2>/dev/null)" ]; then
          echo "conveyor: card $1: its checks or tests failed on main with the change of card $(jq -r .on "$3.stack"), which has not passed its own yet: it waits on, and runs them again after that card"
          readyput "$3" '. + {stackred: true}' || rm -f "$3.ready"
          trc=''; began "$1" "$2" "$5"; continue
        fi
        [ "$trc" = 0 ] || { waitsec=$((wb + SECONDS - ws)); locked waitlap "$1" "$3" || :; return 4; }
        # Its test files' times go on its test line (testlist.sh slowtests()).
        trc=''; slowtests "$3" || :
        record "$1" "$2" test pass "$(jq -cn --slurpfile x <(testrec "$3" 0 "$sec") --slurpfile r <(firstrun "$3" pass) --slurpfile s <(slowrec "$3") '$x[0] + $r[0] + $s[0]')"
        testrulespass > /dev/null
        tested "$3"; began "$1" "$2" "$5"; continue
      fi
      # With batches off it runs no check and no test while it waits on another card (its files or the landing turn;
      # the owner, 2026-11-25: cards that depend on each other wait their turn): it runs its Test step once, at its
      # turn, on main as it is after that card landed (cardtest(), lib/cardland.sh).
      : > "$3.idle"; sleep "$LIVE"; continue
    fi
    # The wait ended: a later wait of this call begins anew, what the card waited before it counted once.
    # Its slot under the cap may have gone to a held card while it waited: it waits for room first (capowed(), lib/cardland.sh).
    rm -f "$3.idle" "$3.nocap"; [ -z "$waited" ] || { rm -f "$3.live"; waited=''; locked waitlap "$1" "$3" || :; }; capowed "$1" "$2" "$3" "$5"
    old=$(git -C "$3" rev-parse HEAD 2>&1) || { block "$1" "$2" "$3" "$5: the engine could not read the commit of the worktree:${old:0:300}"; return 1; }
    [ "$old" != "$(git rev-parse "$onto" 2>/dev/null)" ] || return $moved
    # Stacked, it is reviewed again on the base. A stacked card that waits no more (that card landed, or failed its
    # tests) is not put back on the base it left: a change that no longer applies on main is brought there by a session.
    # One that leaves its stack's base: its tests passed there with that card's change (tested()), which is no pass of
    # its change alone (readysince()), so they run again on main before it lands (testedhere(), card()).
    if [ -n "$stk" ]; then moved=2; caught=''
    elif [ "$old" = "$(jq -r .base "$3.stack" 2>/dev/null)" ]; then caught=''
      readyput "$3" 'del(.tested)' || rm -f "$3.ready"
    fi
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
        readyput "$3" 'del(.tested)' || rm -f "$3.ready"
        parsecheck=1; rm -f "$3.base"; return $moved
      fi
      err=$(git -C "$3" reset -q --hard "$onto" 2>&1) \
        || { block "$1" "$2" "$3" "$5: the engine could not remove the three-way merge of the card onto main:${err:0:300}"; return 1; }
    fi
    # The fast resolver (fastfit()): one judge call merges the conflicts, with no fitting session and no second review
    # (the owner's pick, 2026-11-18): as after a union merge, its tests are not taken as passed (testedhere()), so the
    # merged files' parse check and its tests run on them before it lands.
    if fastfit "$3" "$cf" "$onto" "$mt"; then
      readyput "$3" 'del(.tested)' || rm -f "$3.ready"
      echo "conveyor: card $1: the fast resolver merged its conflicts with main in $(printf '%s' "$cf" | grep -c .) file(s), with no fitting session; its tests run again on the merged files"
      # The owner's yes to a lint policy change covers one policy diff (lintyes()), and no landing gate runs after this
      # merge: a policy diff (lintpolicy()) that is not the one the gate let through (card()'s ph, cardready()) stops
      # for the yes again, as there, keeping its hash. Its places are widened at least as far as in ph (lintpolicy()).
      if lintrule; then
        { packget lint t && t=$(lintpolicy "$3" "$(git -C "$3" rev-parse HEAD)" "$t" "$(pw=${ph:-}; printf '%s' "${pw#* }")"); } || { block "$1" "$2" "$3" "lint: the engine could not read the lint policy files that the change changes, so nothing landed"; return 1; }
        if [ -n "$t" ] && [ "${t%%$'\n'*}" != "${ph:-}" ]; then
          jq -c --arg p "${t%%$'\n'*}" '{body, policy: $p}' <<<"$6" > "$3.body"
          block "$1" "$2" "$3" "${LINTYES}it changes lint policy: $(tail -n +2 <<<"$t" | jq -Rrs 'split("\n") | map(select(. != "")) | join(", ")')" post; return 1
        fi
      fi
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
    # its test pass stand once its push checks pass on its new change (docstested()), so only its product checks run
    # before it lands. It claims again, as one that kept its claim.
    if [ -n "$docs" ] && [ "$(cardpatch "$3" ':(exclude)*.md')" = "$docs" ]; then [ -z "$dp" ] || docstested "$1" "$3"; continue; fi
    moved=2
    [ -z "$away$stk" ] || return 2
  done
}

# Batches. The test step runs 10 to 25 minutes, so cards that share files and are ready to land land together, on one
# test run. A card ready to land: one whose own product checks and changed tests passed after a GO, its message and
# commit trailers written (<worktree>.ready: {issue, msg, extra, tested, tree and head: the tree and commit they passed on, since: when
# they passed; alone: a card that files a last NO-GO's follow-ups, never in a batch}), gone past by no ordered or ready card since: one that waits at its landing claim (settle(); not one away,
# giveway()), or the card whose turn it is (card()). When a
# card's turn to land comes and it is ready, it takes the landing turn (turntake(); none forms while another card has
# it, and it returns 2), then every ready card that waits on that turn (turnq(), whatever its files) or shares a file
# with it or with one taken before it, in turn, up to the pack's landBatch cards in all, never one that shares a file
# with another card that holds it. The batch is in the control record's order first, then by when each card became ready, the card whose
# turn it is among them; a card stacked on a card of the batch (stackto()) after the others, its change being made on
# that card's. That card's claim then holds the files of the whole batch (paths) and keeps the batch's
# change, so no card whose change does not apply with the batch's lands on one of them while the batch is tested (claim()).
# Its own checks and tests passed on what the card's worktree holds now: it is ready (<worktree>.ready, when it has one),
# with what that run passed (units and cases, testlist.sh passlist(); none when it left no list) for a batch that takes it (batchkeep()).
# The identity of a card's staged change, whatever commit it is on: its own added and removed lines, with no line of
# context (-U0), so a change merged three-way onto a main that moved around it is the same change (fits(), settle());
# of the files <pathspec> names when it is given. Empty when the change is. The id is diffid()'s: whitespace counts, so a
# change that only re-indents is another change (Python and YAML read indent), and the line numbers do not.
cardpatch() { local p r; p=$(git -C "$1" diff --cached --binary --no-renames -U0 HEAD -- "${@:2}" 2>/dev/null | diffid 2>/dev/null); r=$?; [ -z "$p" ] || printf '%s\n' "$p"; return $r; } # <worktree> [pathspec...]
tested() { [ ! -e "$1.ready" ] || readyput "$1" 'del(.units, .cases) + {tested: true, tree: $t, head: $h, patch: $p, since: now} + if $u then $u | {units, cases} else {} end' \
  --arg t "$(git -C "$1" write-tree)" --arg h "$(git -C "$1" rev-parse HEAD)" --arg p "$(cardpatch "$1")" --argjson u "$(jq -ce objects "$1.passed" 2>/dev/null || echo null)" || rm -f "$1.ready"; } # <worktree>
# A card whose change a session changed in documentation (*.md) alone, its change outside it the one whose tests passed
# (settle(), cardlanding() in lib/cardland.sh): its test pass stands (tested()) only once the push checks pass on its new
# change (pushgatewait(), lib/contract.sh), as they select by changed files and a .md file can fail one. A batch takes
# a card on that mark alone (gather()), and a tested card runs no push check while it waits (settle()). On a failure
# its <worktree>.ready is removed: no batch takes it, and its landing gate (pushgate()) blocks it at its turn.
docstested() { [ ! -e "$2.ready" ] || { pushgatewait "$1" "$2" && tested "$2"; }; } # <card> <worktree>
# <worktree>.ready rewritten by <jq filter> (with its jq args), under <worktree>.ready.lock, which readyrm() takes too;
# nothing when it has none, 1 when it could not be written.
readyput() { # <worktree> <jq filter> [jq args...]
  local lock r=0 tmp=$1.ready.new.$BASHPID # read here: $BASHPID in jq's redirect would be jq's own pid, not mv's name
  [ -e "$1.ready" ] || return 0
  { exec {lock}>>"$1.ready.lock"; } 2>/dev/null && flock "$lock" || return 1
  if [ -e "$1.ready" ]; then
    jq -c "${@:3}" "$2" "$1.ready" > "$tmp" && mv -f "$tmp" "$1.ready" || { rm -f "$tmp"; r=1; }
  fi
  exec {lock}>&-; return $r
}
# <worktree>.ready removed under <worktree>.ready.lock: a readyput() that read the file before an unlocked removal
# puts it back at its rename, and a batch can take the card again (gather()).
readyrm() { # <worktree>
  local lock
  { exec {lock}>>"$1.ready.lock"; } 2>/dev/null && flock "$lock" || { rm -f "$1.ready"; return; }
  rm -f "$1.ready"; exec {lock}>&-
}
# Whether they passed on the change it holds now: the same staged change, on whatever commit (owner, 2026-11-13: a
# change that passed its tests and still applies to a main that moved is not tested again; each landing made every
# other card run its tests anew, and one card landed per test run). The pass stands whatever test files the cards
# landed since touch (owner, #1777): two changes that fail together show on main, as main red.
testedhere() { jq -e --arg p "$(cardpatch "$1")" '.tested == true and $p != "" and .patch == $p' "$1.ready" >/dev/null 2>&1; } # <worktree>
# When its tests passed (since, tested()), for a card whose tests passed on the change it holds (testedhere()), not on
# a stack's base (stackto(): there they ran with another card's change); fails for any other card (claim()). While its
# worktree is lent to its batch (<worktree>.lent, batch(), rebatch()), the change it holds is its own (bpid()), not the
# batch's the worktree has then: else a later ready card would go past it there, and land() would refuse the batch.
readysince() { # <worktree> [<that read, made by the caller: "<patch>\t<since>", or empty>]
  local s p h r
  # One read of <worktree>.ready (#595): its since and the patch-id its tests passed on, then that patch-id is matched.
  # claim() makes that read in its own jq, for every card at once (rs()), and gives it here.
  if [ $# -gt 1 ]; then r=$2
  else r=$(jq -er 'select(.tested == true and (.since | type) == "number") | "\(.patch | strings // "")\t\(.since)"' "$1.ready" 2>/dev/null) || return 1; fi
  p=${r%%$'\t'*} s=${r#*$'\t'}
  [ -n "$p" ] || return 1
  if [ -s "$1.lent" ]; then
    h=$(<"$1.lent") && [ "$(bpid "$1")" = "$p" ] || return 1
  else h=$(git -C "$1" rev-parse HEAD 2>/dev/null) && [ "$(cardpatch "$1")" = "$p" ] || return 1; fi
  { [ ! -e "$1.stack" ] || ! jq -e --arg h "$h" '.base == $h' "$1.stack" >/dev/null 2>&1; } && printf '%s\n' "$s"
}
gather() { # <card> <worktree> <the card's pid>; under the lock: prints the batch's cards in order, one a line (nothing when it takes none), each other one marked taken (<worktree>.batch); 2 when another card has the landing turn
  local max ord o r x s m all d bc=()
  packget landBatch max && [ "$max" -gt 1 ] && jq -e '.tested == true and .alone != true' "$2.ready" >/dev/null 2>&1 || return 0
  turntake "$1" "$3" || return 2
  ord=$(ctl 2>/dev/null) && ord=$(jq -c .order <<<"$ord") || ord='[]'
  o=$(for r in "$CARDS"/*.claim; do
      [ -e "$r" ] && [ "$r" != "$2.claim" ] || continue
      # One jq a card (#595): its claim, with its <worktree>.ready (null when it is not one JSON object) and the card its
      # <worktree>.stack is on ("" when none), as "<pid> <claim>".
      r=${r%.claim}; { x=$(<"$r.ready"); } 2>/dev/null || x=''; { s=$(<"$r.stack"); } 2>/dev/null || s=''
      r=$(jq -r --arg c "${r##*/}" --arg x "$x" --argjson t "$([ -e "$r.batch" ] && echo true || echo false)" --arg s "$s" \
        '([$x | try fromjson catch null | objects] | first) as $x | ([$s | try fromjson catch null | .on? // empty | if type == "string" then . else tojson end] | first // "") as $s
        | select((.pid | type) == "number" and (.paths | type) == "array") | "\(.pid) \(. + {card: $c, ready: $x, taken: $t, stack: $s} | tojson)"' "$r.claim" 2>/dev/null) || continue
      [ -z "$r" ] || ! kill -0 "${r%% *}" 2>/dev/null || printf '%s\n' "${r#* }"
    done | jq -sc .) && x=$(jq -c --arg c "$1" --slurpfile r "$2.ready" '{card: $c, paths, ready: $r[0]}' "$2.claim") || return 1
  all=$(stdb ask lines cards | jq -cn --slurpfile os <(printf '%s' "$o") --slurpfile mes <(printf '%s' "$x") --argjson ord "$ord" --argjson max "$max" '
      $os[0] as $o | $mes[0] as $me | def meets($a; $b): ($a - ($a - $b)) != [];
      def rank: .ready.issue as $i | ($ord | index($i)) // ($ord | length);
      [inputs | select(.step | IN("landed", "closed", "blocked")) | .card] as $ended
      | [$o[] | select(.card | IN($ended[]) | not)] as $o | [$o[] | select(.held == true) | .paths[]] as $held
      | [$o[] | select(.held != true and .passed != true and (.away != true or .back == true) and (.taken | not) and (.ready | type) == "object" and .ready.tested == true and .ready.alone != true
          and (meets(.paths; $held) | not))] | sort_by([rank, .ready.since])
      | {p: $me.paths, b: [], c: .}
      | def joins($p): .turn == true or meets(.paths; $p);
        until((.b | length) >= $max - 1 or (. as $s | [.c[] | joins($s.p)] | any | not);
          . as $s | ([.c[] | joins($s.p)] | index(true)) as $i | {p: (.p + .c[$i].paths), b: (.b + [.c[$i]]), c: (.c[:$i] + .c[$i + 1:])})
      | select(.b != []) | ([$me] + .b) as $in
      | {paths: (.p | unique), cards: ($in | sort_by([(.stack as $s | $in | any(.card == $s)), rank, .ready.since]) | map(.card))}') || return 1
  [ -n "$all" ] || return 0
  jq -c --slurpfile a <(printf '%s' "$all") '.paths = $a[0].paths' "$2.claim" > "$2.claim.new" && mv -f "$2.claim.new" "$2.claim" && mapfile -t bc < <(jq -r '.cards[]' <<<"$all") || return 1
  # The change that claim keeps is now the batch's: each card's staged change on main, in the batch's order, so a card
  # whose change applies with the whole batch does not wait on it (together()). A card whose change does not apply on
  # those before it is left out, as the batch's test run leaves it out (batch()).
  d=$(mktemp -d) || return 1
  GIT_INDEX_FILE=$d/index git read-tree "refs/heads/$BRANCH" 2>/dev/null || x=''
  for m in "${bc[@]}"; do
    [ -n "$x" ] && git -C "$CARDS/$m" diff --cached --binary --no-renames > "$d/patch" 2>/dev/null || { x=''; break; }
    GIT_INDEX_FILE=$d/index git apply --cached "$d/patch" 2>/dev/null || :
  done
  [ -n "$x" ] && GIT_INDEX_FILE=$d/index git diff --cached --binary --no-renames "refs/heads/$BRANCH" > "$2.cpatch.new" 2>/dev/null && mv -f "$2.cpatch.new" "$2.cpatch" \
    || rm -f "$2.cpatch" "$2.cpatch.new"
  rm -rf "$d"
  for m in "${bc[@]}"; do
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
# card of the run brings its passes: its own (the units of <worktree>.ready, testlist.sh passlist(), when they passed on the change
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
    && p=$(GIT_INDEX_FILE=$i git -C "$1" diff --cached --binary --no-renames -U0 "$b" 2>/dev/null | diffid 2>/dev/null); r=$?
  rm -f "$i"; [ -z "${p:-}" ] || printf '%s\n' "$p"; return $r
}
batchkeep() { # <card> <worktree> <the run's cards>
  local c=$1 wt=$2 m w ps r t a=()
  shift 2
  # One jq for all the run's cards (#595): each card's name, patch-id, <worktree>.ready and .bpass as their text, and
  # how many paths its change has, then those paths; a file that is not one JSON object is none (null).
  for m in "$@"; do
    w=$CARDS/$m; [ "$m" != "$c" ] || w=$wt
    mapfile -d '' ps < <(git apply --numstat -z "$w.bpatch" 2>/dev/null); ps=("${ps[@]#*$'\t'*$'\t'}")
    { r=$(<"$w.ready"); } 2>/dev/null || r=''; { t=$(<"$w.bpass"); } 2>/dev/null || t=''
    a+=("$m" "$(bpid "$w")" "$r" "$t" "${#ps[@]}" "${ps[@]}")
  done
  jq -cn '
    def obj: [try fromjson catch null | objects] | first;
    def cards: if . == [] then empty else (.[4] | tonumber) as $n
      | {card: .[0], patch: .[1], ready: (.[2] | obj), bpass: (.[3] | obj), paths: .[5:5 + $n]}, (.[5 + $n:] | cards) end;
    def file: split("\t")[0];
    def meets($u; $v): ($u | file) == ($v | file) and ($u == $v or ($u | contains("\t") | not) or ($v | contains("\t") | not));
    [$ARGS.positional | cards] as $all
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
       all: ($ch == [] and ($keep | length) == ($units | length))}' --args "${a[@]}"
}
# The list a batch run is given (CONVEYOR_TEST_RERUN, tests()): what batchkeep() keeps, as `pass` (a whole file) and
# `ok` (a case) lines, and its `changed` files. A file every unit of which it keeps is one `pass` line, not its cases'
# `ok` lines: a command that cannot run a file's cases apart (any shell test but the engine's runner) honours only
# `pass`, and would run whole again a file passed whole that it kept case by case. None when it keeps nothing and names
# no file: the run's own list stands.
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
# its own passes (<worktree>.ready, still on its change) have, else, when none has it, each card whose own have a unit
# of its file, else each card with no own passes, else every card, as the run's combined change selected it. Bug: a
# case main added to one card's test file was in no card's own cases, so it went to every card.
batchpass() { # <card> <worktree> <units json> <cases> <the run's cards>
  local c=$1 wt=$2 u=$3 n=$4 m w x r a=()
  shift 4
  # One jq for all the run's cards (#595): each card's name, patch-id and <worktree>.ready as its text (none, null, when
  # it is not one JSON object).
  for m in "$@"; do w=$CARDS/$m; [ "$m" != "$c" ] || w=$wt
    { r=$(<"$w.ready"); } 2>/dev/null || r=''; a+=("$m" "$(bpid "$w")" "$r"); done
  x=$(jq -cn --argjson u "$u" --argjson n "$n" '
      def file: split("\t")[0];
      def meets($a; $b): ($a | file) == ($b | file) and ($a == $b or ($a | contains("\t") | not) or ($b | contains("\t") | not));
      [$ARGS.positional as $a | range(0; $a | length; 3) | {card: $a[.], patch: $a[. + 1], ready: ([$a[. + 2] | try fromjson catch null | objects] | first)}]
      | [.[] | . as $m | {card, own: (.ready | if (type) == "object" and .tested == true and $m.patch != "" and .patch == $m.patch then
          [.units | arrays] | first else null end)}] as $ms
      | [$u[] | . as $x | first([$ms[] | select(any(.own[]?; meets(.; $x))) | .card], [$ms[] | select(any(.own[]?; file == ($x | file))) | .card],
           [$ms[] | select(.own == null) | .card], [$ms[].card] | select(. != []))[] | {card: ., unit: $x}] as $e
      | {cards: (map({(.card): .patch}) | add), units: $u, cases: $n,
         by: (reduce $ms[].card as $c ({}; .[$c] = [$e[] | select(.card == $c) | .unit]))}' --args "${a[@]}") || return 0
  for m in "$@"; do w=$CARDS/$m; [ "$m" != "$c" ] || w=$wt; printf '%s\n' "$x" > "$w.bpass"; done
}
# The batch's one test run, in the card's worktree: each card's patch on the ones before, in the batch's order. Which
# cards stay in it is found in that order, on main: a card whose patch does not apply on top of those kept before it,
# or whose product checks fail, leaves the batch: it waits on at its claim and is fitted afterwards, as any waiting card
# is. When that is the card's own patch, the card is apart (sets apart): the others are tested and land without it,
# then it is fitted onto main as they left it (card()); the batch returns 0, its own tests having passed. Should the card's own patch not apply in a run (a card it came after left), the batch is given up: the
# cards not yet judged wait on at their claims, and the card is tested alone. Red, the batch is split, no test left out: its
# first half, then its second on top of what passed, down to single cards. Each run is of the lint gate (lintbatch()),
# then the product checks, on the change of the cards in it, then the tests; a lint finding or execution error and a
# check that fails are red runs. A card red alone on top of what passed for its lint leaves the batch with no test
# failure (lintleave(): by apart when it is the card, else unbatched), its landing gate dealing with it on main. A second half whose first half passed whole
# is what just failed, so it is split with no run of its own (a single card is still run, for its output). A card red
# alone on top of what passed is the one that breaks it: a card it took is told its exit, given that run's output
# and coverage (<worktree>.test, .uncovered), and goes to its fix as if its own tests failed. Sets mates (the cards that passed, the card among
# them, in order; none when no other card passed); the card's worktree is left as it was, the output of the run that
# judged the card in <worktree>.test (its coverage in .uncovered), and TEST_BATCH (for the selected of its test line: {cases: 0, kept} when what
# judged it ran no case and kept that many passes; {kept} when it ran the rest with batchkeep()'s list, its log
# saying what it ran; else empty).
# A run reuses each card's passed tests (the owner, 2026-11-13, issue #346; batchkeep()): it does not run a case a card
# passed on its own change, unchanged since (the same patch-id as in its <worktree>.ready), when no other card of the
# run selects it, nor a case the last batch run that passed passed for cards still in this one, on their unchanged
# changes. It runs the rest: the cases two or more cards select together, and every case of a card whose pass no
# longer holds. A run with none of those left runs nothing, and passes. Given up for it: two changes that each passed
# alone can fail together in a case only one of them selects; the whole test on main is the net.
batch() { # <card> <worktree> <the batch's cards, in order, the card among them>; returns the exit of the run that judged the card
  local c=$1 wt=$2 m s t out rc lrc=1 id half split=0 whole='' todo=() in=() good=() k=() lost='' bw='' br='' bf='' bz='' keep bt bb='' lr
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
      rm -rf "$wt.batchtest" "$wt.batchtestlog" "$wt.batchfirst" "$wt.batchuncovered" "$wt.batchnoresult"; echo "conveyor: card $c: its change no longer applied in its batch, so it is tested alone"; tests "$wt"; return
    fi
    [ ${#in[@]} != 0 ] || continue
    bt=''; TEST_REFUSED=''; lr=''
    if [ "$half" = 1 ] && [ "$whole" = "$id" ] && [ ${#in[@]} = ${#s[@]} ] && [ ${#in[@]} -gt 1 ]; then rc=1
    else
      k=("${good[@]}" "${in[@]}"); echo "conveyor: card $c tests a batch of ${#k[@]}: ${k[*]}"
      t=$SECONDS
      # The lint gate for a batch first (lintbatch(), lib/lint.sh): a finding or an execution error is a red run (lr)
      # for the split only; the card it finds leaves the batch (lintleave(), below).
      if ! lintbatch "$c" "$wt" "${k[@]}"; then rc=1; lr=1; norun "$wt" "the lint check failed on the change of ${k[*]}"
      elif ! out=$(checks "$wt"); then rc=1; norun "$wt" "a product check failed on the change of ${k[*]}:"$'\n'"$out"
      # Every case the run would run passed on its cards' changes (batchkeep()): no run.
      elif keep=$(batchkeep "$c" "$wt" "${k[@]}") && jq -e .all <<<"$keep" >/dev/null; then
        rc=0; bt=$(jq -c '{cases: 0, kept}' <<<"$keep")
        norun "$wt" "no case to run: each passed on the change of the card that selects it, or in a batch run with each card that does: ${k[*]}"
        echo "conveyor: card $c: its batch of ${#k[@]} runs no case, each having passed on its cards' changes ($(jq .kept <<<"$keep") kept): ${k[*]}"
        batchpass "$c" "$wt" "$(jq -c .units <<<"$keep")" "$(jq .kept <<<"$keep")" "${k[@]}"
      else
        # The passes the list keeps are counted here: a file it keeps whole is not run, so no log counts its cases.
        if [ -n "$keep" ] && batchlist "$wt" "$keep"; then bt=$(jq -c '{kept}' <<<"$keep" 2>/dev/null) || bt=''; fi
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
      if [ -n "$lr" ]; then lintleave "$c" "$wt" "$m"
      elif [ "$m" = "$c" ]; then lrc=$rc; keeprun "$wt" "$wt.batchtest" "$wt.batchtestlog" "$wt.batchfirst" "$wt.batchuncovered" "$wt.batchnoresult"; bw=$TEST_WAIT br=$TEST_RUN bf=$TEST_FREE bz=$TEST_REFUSED bb=$bt
      elif [ $rc != 0 ]; then
        keeprun "$wt" "$CARDS/$m.test" "$CARDS/$m.testlog" "$CARDS/$m.first" "$CARDS/$m.uncovered" "$CARDS/$m.noresult" && jq -c --argjson r "$rc" --argjson s "$t" '. + {fail: $r, sec: $s}' "$CARDS/$m.batch" > "$CARDS/$m.batch.new" && mv -f "$CARDS/$m.batch.new" "$CARDS/$m.batch"
      fi
    done
  done
  git -C "$wt" reset -q --hard && git -C "$wt" apply --index "$wt.bpatch" || { unbatch "${good[@]}"; norun "$wt" "the card's change could not be put back in its worktree after its batch's tests"; return 1; }
  [ ! -e "$wt.batchtest" ] || { rm -f "$wt.uncovered"; [ ! -e "$wt.batchuncovered" ] || mv -f "$wt.batchuncovered" "$wt.uncovered"; }
  [ ! -e "$wt.batchtest" ] || { rm -f "$wt.noresult"; [ ! -e "$wt.batchnoresult" ] || mv -f "$wt.batchnoresult" "$wt.noresult"; } # the card's own run says why it gave no result (voidrun())
  rm -f "$wt.first"; [ ! -e "$wt.batchtest" ] || { rm -rf "$wt.testlog"; mv -f "$wt.batchtest" "$wt.test"; [ ! -d "$wt.batchtestlog" ] || mv -f "$wt.batchtestlog" "$wt.testlog"; [ ! -e "$wt.batchfirst" ] || mv -f "$wt.batchfirst" "$wt.first"; TEST_WAIT=$bw TEST_RUN=$br TEST_FREE=$bf TEST_REFUSED=$bz TEST_BATCH=$bb; }
  [ ${#good[@]} -lt 2 ] && [ "${good[0]:-$c}" = "$c" ] || mates=("${good[@]}")
  [ -z "$apart" ] || return 0
  return $lrc
}

# A batch whose run passed while main moved (a card on other files landed during it) lands on that run, with no second
# one (owner, 2026-11-13: the batch holds the shared files through every run, so every card waiting on them waited for
# one more run of 5 to 10 minutes each time another card landed). Both must hold: no card of it has changed since the
# run (its staged change is the patch the run applied), and its changes still apply, in its order, to main as it is
# now. They are applied there in the card's worktree and the lint gate for a batch (lintbatch()) and the product checks
# run on the combined change (again, on main as it is then, each time main moves during them, so a card landing
# meanwhile costs no batch run): a lint finding or execution error and a check that fails are a red run of the batch,
# as in batch() (where the card the split finds for its lint leaves the batch, lintleave()): with the card and another card in it, the card's worktree is left on
# main as it is now with its change, mates the cards in it, and it returns 3 for card() to run the batch there
# (batch() splits it and sends the card that breaks it to its fix); else the batch is tested again, as when a card of
# it changed. Test files the cards landed during the run touch do not matter: the batch's pass stands (owner, #1777;
# testedhere()). A card whose change no longer applies there leaves the batch
# and is fitted afterwards, as any waiting card is; the others land. When that is the card itself it is apart
# (sets apart), as in batch(). Sets mates to the cards that land. The card among them, its worktree is left on main as
# it is now with its change, where land() finds the batch's run. Else it is left there with no change, for the others'
# landing, and back names the commit the card's change goes back onto after it (card()). Returns 1 when the batch is
# to be tested again, the worktree as it was; 2 when the card's change could not be put back in its worktree; 3 for a
# red run (above).
rebatch() { # <card> <worktree>; card()'s mates is the batch
  local c=$1 wt=$2 m old new k=() left=() gone x
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
      # The lint gate for a batch first (lintbatch(), lib/lint.sh), x saying which failed: a red run as a check's is.
      m=''; x=''
      if ! lintbatch "$c" "$wt" "${k[@]}"; then x='the lint check'
      elif ! m=$(checks "$wt"); then x='a product check'; fi
      if [ -n "$x" ]; then
        m=${m//$'\n'/ }; [ -z "$m" ] || m=": ${m:0:300}"
        if [ -z "$gone" ] && [ ${#k[@]} -gt 1 ]; then
          git -C "$wt" reset -q --hard 2>/dev/null && git -C "$wt" apply --index "$wt.bpatch" 2>/dev/null || { asitwas || return 2; return 1; }
          echo "conveyor: card $c: $x failed on its batch's change on main as it is now, a red run, so the batch is run again there$m"
          [ ${#left[@]} = 0 ] || unbatch "${left[@]}"
          mates=("${k[@]}"); return 3
        fi
        asitwas || return 2; echo "conveyor: card $c: $x failed on its batch's change on main as it is now, so the batch is tested again$m"; return 1
      fi
      # Main moved again during the checks: the batch is fitted onto main as it is now and they run there, not its tests.
      m=$(git rev-parse "refs/heads/$BRANCH" 2>/dev/null) && [ "$m" != "$new" ] && { new=$m; continue; }
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
# What land() prints while a release run is under way (relhold(), lib/push.sh): card() waits for it to end (releasewait()).
RELHELD="a release run is under way, so no card lands on main until it ends; nothing was landed"
# The landing turn: the merge queue, with batches on (issue 1311: a few cards that ran their tests again each time main
# moved held 62% of all test time). <cards folder>/land.turn holds {card, pid}. A ready card takes the turn at its claim
# (turnq()) or when its batch forms (gather()), and keeps it through its batch's run to its landing. While it has it, no
# other card lands (land() prints TURNHELD; a batch that holds that card lands), and a card at its land step waits for
# it (landwait()), so main does not move between that run and its landing. A ready card that finds another card with the
# turn does not test or land: it waits on that card, holding nothing, and the next batch takes it, whatever files it
# changes. The turn ends when its card lands (land()), gives way (giveway()), waits on another card at its claim
# (settle()), blocks (block() removes its claim) or fails its tests (card()), and when its process ends.
TURNHELD="another card has the landing turn, as its batch lands first; nothing was landed"
# A ready card (readysince(); not one that files follow-ups) that claim() lets go on, with batches on: it takes the
# landing turn, or, while another card has it, waits on that card. Prints that wait ({on, paths: [], turn: true}: no
# stack on that card, settle()) or nothing; fails when the turn could not be written. Not a card a batch took
# (<worktree>.batch): that batch lands it or sends it back (settle()), and a turn it took then would outlive it. Under the lock.
turnq() { # <card> <worktree> <the card's pid>
  local o b
  [ -e "$2.ready" ] && [ ! -e "$2.batch" ] && packget landBatch b && [ "$b" -gt 1 ] && jq -e '.tested == true and .alone != true' "$2.ready" >/dev/null 2>&1 && readysince "$2" >/dev/null || return 0
  if o=$(turnon) && [ "$o" != "$1" ]; then jq -cn --arg o "$o" '{on: $o, paths: [], turn: true}'; else turntake "$1" "$3"; fi
}
# The cards of a batch that passed land without the card whose turn it is (card(): it broke the batch, or its change
# did not apply on theirs): its turn ends first, under the same lock, else land() would refuse them (TURNHELD).
landmates() { turnfree "$1" && land "${@:2}"; } # <card> <land()'s arguments>; under the lock
turnon() { # prints the card that has the landing turn; fails when none has it
  local c p
  IFS=$'\t' read -r c p < <(jq -r 'objects | "\(.card)\t\(.pid)"' "$CARDS/land.turn" 2>/dev/null) || return 1
  [ -n "$c" ] && [[ $p =~ ^[0-9]+$ ]] && kill -0 "$p" 2>/dev/null && [ -e "$CARDS/$c.claim" ] && printf '%s\n' "$c"
}
turntake() { # <card> <the card's pid>; under the lock: fails when another card has the turn
  local o
  ! o=$(turnon) || [ "$o" = "$1" ] || return 1
  jq -cn --arg c "$1" --argjson p "$2" '{card: $c, pid: $p}' > "$CARDS/land.turn.new" && mv -f "$CARDS/land.turn.new" "$CARDS/land.turn"
}
turnfree() { [ "$(jq -r '.card' "$CARDS/land.turn" 2>/dev/null)" != "$1" ] || rm -f "$CARDS/land.turn"; } # <card>; under the lock
# The order of the cards that wait on the files of <card>, fixed as <card> starts its Test step (cardtest(),
# lib/cardland.sh; the owner, 2026-11-25: cards that depend on each other wait their turn). Each live claim that waits on
# <card> (claimline(): on) for its files (not turn), with no place in the order yet (after), joins the order: of those,
# the earlier in the control record's order first, then the older pick. Each lands after the last card before it in
# the order that shares a file with it, else after <card>. Its claim then names the card it lands after (after), and
# claim() keeps it waiting on that card while that card has a live claim on one of its files. A card that starts its
# Test step again (after a fix round) adds the cards that came to wait on it since. Under the lock.
orderfix() { # <card>
  local o r c ord t x a
  o=$(for r in "$CARDS"/*.claim; do
      [ -e "$r" ] && [ "$r" != "$CARDS/$1.claim" ] || continue
      c=${r##*/}
      r=$(jq -r --arg c "${c%.claim}" 'select(.held != true and (.pid | type) == "number" and (.paths | type) == "array") | "\(.pid) \({card: $c, paths, on, after, turn} | tojson)"' "$r" 2>/dev/null) || continue
      [ -z "$r" ] || ! kill -0 "${r%% *}" 2>/dev/null || printf '%s\n' "${r#* }"
    done | jq -sc .) || return 1
  [ "$o" != '[]' ] || return 0
  ord=$(ctl 2>/dev/null) && ord=$(jq -c '.order // [] | arrays' <<<"$ord") && [ -n "$ord" ] || ord='[]'
  # The claims go to jq by file: one argument over 128 KiB fails to start jq on Linux (claim()).
  t=$(stdb ask lines cards | jq -rn --arg me "$1" --slurpfile o <(printf '%s' "$o") --argjson ord "$ord" '
      $o[0] as $o | [inputs | select(.step == "picked")] as $p | ($p | map(.card)) as $at | ($ord | length) as $n
      | def rank($c): ($p | map(select(.card == $c)) | first | .issue) as $i | ($ord | index($i)) // $n;
        def chain($t; $k): ([$o[] | select(.after == $t)] | first) as $x | if $x == null or $k >= 100 then [] else [$x] + chain($x.card; $k + 1) end;
      [$o[] | select(.on == $me and .after == null and .turn != true)] | sort_by(.card as $c | [rank($c), ($at | index($c) // 1e9)])
      | reduce .[] as $c ({l: chain($me; 0), out: []};
          ([.l[] | select((.paths - (.paths - $c.paths)) != []) | .card] | last // $me) as $a | .l += [$c] | .out += ["\($c.card) \($a)"])
      | .out[]') || return 1
  while read -r x a; do
    [[ $x =~ ^[A-Za-z0-9._-]+$ && $a =~ ^[A-Za-z0-9._-]+$ ]] || continue
    jq -c --arg a "$a" '.after = $a' "$CARDS/$x.claim" > "$CARDS/$x.claim.new" && mv -f "$CARDS/$x.claim.new" "$CARDS/$x.claim" || return 1
    echo "conveyor: card $x lands after card $a: the order of the cards that wait on card $1 is fixed as it starts its Test step"
  done <<<"$t"
}
# A card at its land step waits while another card has the landing turn, as for a release run (releasewait(),
# lib/push.sh): a start line of its land step marked waitFor: turn, its live record naming that card (waits.on: the
# Board's step line says "waiting on #<its issue>", as for a wait at a claim), brought up to date as it waits, and
# <worktree>.idle standing. Its seconds are noted as the wait turn (waitnote(), lib/records.sh).
landwait() { # <card> <issue> <worktree>
  local at o ws
  o=$(turnon) && [ "$o" != "$1" ] || return 0
  record "$1" "$2" start ok '{"of":"land","waitFor":"turn"}'
  at=$(date -u +%FT%TZ) ws=$SECONDS
  while o=$(turnon) && [ "$o" != "$1" ]; do
    jq -cn --arg at "$at" --arg o "$o" '{step: "land", at: $at, last: (now | todate), turns: 0, files: {run: 0, of: null}, tests: null, waits: {on: $o, paths: []},
      action: "waiting for card \($o) to land first: it has the landing turn, as its batch lands first"}' > "$3.live.tmp" 2>/dev/null && mv -f "$3.live.tmp" "$3.live"
    : > "$3.idle"; sleep "$LIVE"
  done
  rm -f "$3.live" "$3.idle"
  [ $((SECONDS - ws)) = 0 ] || waitnote "$1" turn "$((SECONDS - ws))" || :
}
# The landing holds its share of RELLANDING (holdtake(), lib/push.sh) throughout, so a release run that begins
# meanwhile waits for it to end before its suite reads main.
land() { # <card> <issue> <worktree> <commit message> [extra json for the landed line] [those five of each further card of a batch, in its order]
  local hk rc
  holdtake; rc=$?
  [ $rc = 0 ] || { if [ $rc = 1 ]; then echo "$RELHELD"; else echo "the release hold could not be made; nothing was landed"; fi; return 1; }
  hk=$RELHOLDFD
  landone "$@" {hk}>&-; rc=$?; exec {hk}>&-; return $rc
}
landone() { # <the arguments of land()>
  local err sha l p base tip want x i h tn b='[]' a=("$@") g=() ls=() wts=() shas=() paths=() cov='' # cov: the batch's commits so far whose landed lines a push reads as reviewed (contractcovered())
  # Another card has the landing turn (turnon()): none of this one's cards lands before it.
  if tn=$(turnon); then for ((i = 0; i < ${#a[@]}; i += 5)); do [ "${a[i]}" != "$tn" ] || tn=''; done; [ -z "$tn" ] || { echo "$TURNHELD"; return 1; }; fi
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
    err=$(export GIT_INDEX_FILE="$3.index" "${g[@]}"; commithook pre-commit 2>&1 && commithook commit-msg "$3.msg" 2>&1); h=$? # commithook(): lib/push.sh
    [ "$tip" = "$base" ] || git worktree remove --force "$3.head" 2>/dev/null
    [ $h = 0 ] || { echo "commit refused: ${err:0:600}"; return 1; }
    [ "$(GIT_INDEX_FILE="$3.index" git write-tree)" = "$want" ] || { echo "main's hooks changed what would be committed: it is not exactly the reviewed diff; it needs $OWNER"; return 1; }
    sha=$(git commit-tree "$want" -p "$tip" -F "$3.msg") || { echo "cannot make the commit object"; return 1; }
    # The persisted-contract check (contractrange(), lib/contract.sh) on the commit that lands, as main's pre-push hook
    # runs it (from each base a push can start at): a later card of a batch lands on the commit before it, which its own
    # checks never read. A refusal or a check that cannot run lands nothing, and the card is no longer ready, so no batch
    # takes it again; it goes back to its landing gate (contractgate(), from cardland(), lib/cardland.sh). The batch's
    # cards before it that a push reads as reviewed once their landed lines are written (cov) start no check.
    contractrange . "$tip" "$sha" "$cov" || { readyrm "$3"; echo "contract: the persisted-contract check refuses card $1's change on the commit it would land on, or could not run; nothing was landed: ${CONTRACT_OUT:0:600}"; return 1; }
    p=false; ! product "$sha" || p=true
    ls+=("$(jq -c --arg s "$sha" --argjson p "$p" '. + {sha: $s, product: $p}' <<<"$x")"); wts+=("$3"); shas+=("$sha"); tip=$sha
    ! contractcovered "$x" || cov+=$sha$'\n'
  done
  onmain && [ "$(git rev-parse "refs/heads/$BRANCH")" = "$base" ] || { echo "main moved during the landing; nothing was landed"; return 1; }
  # The checkout gets every card's change in one apply, which writes all or nothing: a change that no longer applies
  # leaves none of the batch's behind.
  err=$(git diff --binary --no-renames "$base" "$tip" | git apply --index 2>&1) || { echo "rebase onto main conflicts: ${err:0:600}"; return 1; }
  git update-ref -m "conveyor ${a[0]}" "refs/heads/$BRANCH" "$tip" "$base" \
    || { echo "main moved during the landing; nothing was landed, and the card's change is left in main's checkout for $OWNER to sort out"; return 1; }
  for i in "${!wts[@]}"; do
    turnfree "${a[i * 5]}"
    # A card the batch took ends the lap of its wait it sleeps in (waitlap()): that lap goes on its landed line.
    [ ! -e "${wts[i]}.batch" ] || waitlap "${a[i * 5]}" "${wts[i]}"
    l=$(line "${a[i * 5]}" "${a[i * 5 + 1]}" landed ok "${ls[i]}") && append "$l" || { echo "landed as ${shas[i]} but the record line failed"; return 1; }
    attemptsgone "$(attemptkey "${a[i * 5 + 1]}" "${a[i * 5]}")" # its issue's attempts record ends with the landing (lib/attempts.sh)
    [ ! -e "${wts[i]}.batch" ] || { jq -c --arg s "${shas[i]}" '. + {landed: $s}' "${wts[i]}.batch" > "${wts[i]}.batch.new" && mv -f "${wts[i]}.batch.new" "${wts[i]}.batch"; }
  done
}
