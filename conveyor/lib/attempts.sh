# SPDX-License-Identifier: Apache-2.0
# The attempts record of an issue (#1820): what each earlier attempt at it tried and how that ended, so a fix round, a
# Test-step fix, a retried card (with or without --fresh) and a follow-up card do not try the same approach again.
# It is <state>/attempts/<key>.jsonl, the key the issue number, or the card id for a card with no GitHub issue
# (attemptkey()). One line an attempt end, written by attempt() alone, at three places: the end of a review fix round
# (cardfix(), lib/card.sh: kind fix), each failed Test step (cardfailed(), lib/cardland.sh: kind testfix) and a block
# (block(), lib/push.sh: kind block); `retry --fresh` adds a line naming the folder its kept work went to (retry(),
# lib/issues.sh: kind fresh). Lines are never edited; the file goes when a card of the key lands (landone(),
# lib/claim.sh). Read by attempts() (fixprompt(), testfixprompt(), lib/card.sh; carried(), lib/issues.sh, the brief
# of a card with no GitHub issue too) and fuattempts() (a follow-up's body, followups(), lib/followups.sh).

# The fields of a line, each cut to its limit: card, round, kind, approach (the session's reply: the fixer's FIXBACK
# note, 600 characters), outcome (the review's verdict, the test result or the block reason, 400), findings (5 at most,
# each its E-id and the judge's reason, 300), tests (the failing case names and the end of the output, 2000) and diff
# (the path of the round's diff).
ATTEMPTCUT='{card: (.card // "" | tostring), round: (.round // 0), kind: (.kind // "" | tostring),
  approach: (.approach // "" | tostring | .[0:600]), outcome: (.outcome // "" | tostring | .[0:400]),
  findings: [(.findings // [])[:5][] | {id: (.id // "" | tostring), reason: (.reason // "" | tostring | .[0:300])}],
  tests: (.tests // "" | tostring | .[0:2000]), diff: (.diff // "" | tostring)}'
# The lines that open and close the section attempts() prints: attemptsin() finds an older copy of it in a brief by them.
ATTHEAD='# Earlier attempts at this issue'
ATTEND='# End of the earlier attempts'
ATTMAX=4000 # the characters attempts() prints at most, its two marker lines too

# The key of <card> of <issue number>: the issue number; for a card with no GitHub issue, the first of the cards it was
# given back from (testcardwas(), lib/testaction.sh: `retry <card id>` gives it back as a new card), else the card
# itself, so a card given back reads and adds to the record of the cards before it.
attemptkey() { # <issue number> <card>
  local w
  [ "${1:-0}" = 0 ] || { printf '%s' "$1"; return 0; }
  w=$(testcardwas "$2" 2>/dev/null | head -n 1)
  printf '%s' "${w:-$2}"
}
# The file of <key>; fails for a key that is not one issue number or card id (a path, or empty).
attemptfile() { # <key>
  [[ $1 =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || return 1
  printf '%s/attempts/%s.jsonl' "$ST" "$1"
}
# Adds one line to the record of <key>. A line that cannot be written is said on stderr: the card goes on without it.
attempt() { # <key> <entry json>
  local f l
  f=$(attemptfile "$1") || { echo "conveyor: attempts: '$1' is no issue number or card id; nothing recorded" >&2; return 1; }
  l=$(jq -c "$ATTEMPTCUT" <<<"$2" 2>/dev/null) && [ -n "$l" ] && mkdir -p "${f%/*}" && printf '%s\n' "$l" >> "$f" \
    || { echo "conveyor: attempts: the entry of $1 could not be written to $f" >&2; return 1; }
}
attemptsgone() { # <key>
  local f; f=$(attemptfile "$1") || return 0; rm -f "$f"
}
# Where the diff a line names (<worktree>.rounds/<round>.diff) is now: there, in its card's kept folder after a block
# (block(), lib/push.sh), or in a folder under kept-dropped after `retry --fresh` (retry(), lib/issues.sh). Nothing
# when it is gone.
attemptdiff() { # <path>
  local c r m
  r=${1##*/}; c=${1%/*}; c=${c##*/}; c=${c%.rounds}
  for m in "$1" "$ST/kept/$c/$c.rounds/$r" "$ST"/kept-dropped/*/"$c/$c.rounds/$r"; do [ ! -f "$m" ] || { printf '%s' "$m"; return 0; }; done
}
# The last 3 lines of the record of <key>, newest first, as a brief section, at most ATTMAX characters in all, its last
# line ATTEND. Each entry gets an even share of the room, and a share a short entry leaves goes to the longer ones, so
# a long entry is cut and never hides another. A diff is named where it is now (attemptdiff()), or not when it is gone.
# Nothing when the record has none.
attempts() { # <key>
  local f p m='{}'
  f=$(attemptfile "$1") && [ -s "$f" ] || return 0
  while IFS= read -r p; do
    m=$(jq -c --arg p "$p" --arg q "$(attemptdiff "$p")" '.[$p] = $q' <<<"$m") || return 0
  done < <(jq -Rrs '[split("\n")[] | fromjson? | objects][-3:][] | .diff | select(. != "")' "$f" 2>/dev/null)
  jq -Rrs --arg h "$ATTHEAD" --arg e "$ATTEND" --argjson max "$ATTMAX" --argjson m "$m" '[split("\n")[] | fromjson? | objects] as $a | select($a != [])
    | ($a[-3:] | reverse | map("\n## \(.kind) \(if .kind == "fix" or .kind == "testfix" then "round \(.round) " else "" end)of card \(.card)"
        + (if .outcome != "" then "\nOutcome: \(.outcome)" else "" end)
        + (if .approach != "" then "\nApproach: \(.approach)" else "" end)
        + (if .findings != [] then "\nFindings:" + (.findings | map("\n- \(.id): \(.reason)") | join("")) else "" end)
        + (if .tests != "" then "\nTests:\n\(.tests)" else "" end)
        + (($m[.diff] // "") as $q | if $q != "" then "\nDiff: \($q)" else "" end))) as $l
    | "\($h)\nThe latest \($l | length) of the \($a | length) attempts the engine recorded for this issue, newest first: what each tried and how it ended. Do not try an approach again that did not hold: take another one.\n" as $top
    | ($l | to_entries | sort_by(.value | length)) as $s
    | (reduce range(0; $s | length) as $i ({b: ($max - ($top | length) - ($e | length) - ($l | length)), o: {}};
        ((.b / (($s | length) - $i)) | floor) as $c | .o[$s[$i].key | tostring] = $s[$i].value[0:$c] | .b -= ([$s[$i].value | length, $c] | min))).o as $o
    | $top + ([range(0; $l | length) | $o[tostring]] | join("\n")) + "\n" + $e' "$f" 2>/dev/null
}
# <prompt> with the section attempts() printed when it was made (in the brief: carried()) taken out, and that of <key>
# now after it. A section with no ATTEND line after its heading (cut short) is kept.
attemptsin() { # <prompt> <key>
  local a; a=$(attempts "$2")
  printf '%s' "$1" | awk -v h="$ATTHEAD" -v e="$ATTEND" '!s && $0 == h { s = 1; b = $0; next }
    s { b = b "\n" $0; if ($0 == e) { s = 0; b = "" }; next } { print } END { if (s) print b }'
  [ -z "$a" ] || printf '\n%s' "$a"
}
# The entry of fix round <round> of <card>, which review <pass> (its verdict <verdict>) sent to it, written when its
# session ends, before the checks after it (checked(), lib/donewhen.sh) can block the card: its session's reply
# (<approach>), the findings that round was told (<numbered() lines>, lib/donewhen.sh), each with the reason the judge
# gave in <review line> when it accepted it (as rounded() keeps it) or else its line, and the path its diff goes to.
fixattempt() { # <key> <card> <worktree> <round> <pass> <verdict> <approach> <numbered() lines> [<review line>]
  local fs
  # The review line goes in by file, as in rounded(): a long one passes Linux's 128 KiB limit for one argument.
  fs=$(jq -cs --slurpfile rv <(printf '%s\n' "${9:-null}") '$rv[0] as $v | map(. as $f
    | {id, reason: ([$v.judge.accepted[]? | objects | select(.finding == $f.line and .reason != null and .cost != null) | .reason] | first // $f.line)})' <<<"$8" 2>/dev/null) || fs='[]'
  attempt "$1" "$(jq -cn --arg c "$2" --argjson r "$4" --arg a "$7" --arg o "review $5 said $6" --argjson f "${fs:-[]}" --arg d "$3.rounds/$4.diff" \
    '{card: $c, round: $r, kind: "fix", approach: $a, outcome: $o, findings: $f, diff: $d}')"
}
# The failing cases of <worktree>'s last test run (<failures json> of testfails(), or null), one a line, then the last
# 40 lines of its output (<worktree>.test), together within the 2000 characters of a line's tests.
attemptstests() { # <worktree> [<failures json>]
  local n t m
  n=$(jq -r '[.files[]? | .file as $f | if (.cases // []) != [] then .cases[] | "- \($f): \(.name // "")" else "- \($f)" end] | join("\n") | .[0:500]' <<<"${2:-null}" 2>/dev/null) || n=''
  t=$(tail -n 40 "$1.test" 2>/dev/null | tr -d '\000')
  [ -z "$n" ] || n+=$'\n'
  m=$((2000 - ${#n})); [ ${#t} -le $m ] || t=${t: -m}
  printf '%s%s' "$n" "$t"
}
# The entry of the failed Test step <round> of <card> (its count of them: the fix round it goes to, or, after the
# last fix round, the failure that blocks it): the reply of the session whose change failed, the run's exit and its
# failures.
testattempt() { # <key> <card> <worktree> <round> <exit> [<failures json>]
  attempt "$1" "$(jq -cn --arg c "$2" --argjson r "$4" --arg a "$(lastreply "$3.out")" --arg o "the changed tests failed (exit $5)" --arg t "$(attemptstests "$3" "${6:-null}")" \
    '{card: $c, round: $r, kind: "testfix", approach: $a, outcome: $o, tests: $t}')"
}
# The entry of a block of <card>, before its evidence moves: the reason's first line, the last session's reply and the
# last test run's failing cases (testfails(), lib/testrun.sh, which reads them from <worktree>.testlog) and the end of
# its output, when there are any; its round the fix sessions it ran (card()'s fixed, 0 outside it).
blockattempt() { # <key> <card> <worktree> <reason>
  local tf=null
  [ ! -s "$3.test" ] || tf=$(testfails "$3.test" 1 2>/dev/null) || tf=null
  attempt "$1" "$(jq -cn --arg c "$2" --argjson r "${fixed:-0}" --arg a "$(lastreply "$3.out")" --arg o "${4%%$'\n'*}" --arg t "$(attemptstests "$3" "${tf:-null}")" \
    '{card: $c, round: $r, kind: "block", approach: $a, outcome: $o, tests: $t}')"
}
# The line `retry --fresh` adds (kind fresh): the record stays, and names where the kept work of each of <cards> (one a
# line) went in <folder> (under the state folder's kept-dropped), so the next card reads both.
freshattempt() { # <key> <folder> <cards>
  local c w=''
  while IFS= read -r c; do [ -n "$c" ] && { [ -e "$2/$c" ] || [ -e "$2/$c.review" ]; } && w+=${w:+, }${2#"$ST"/}/$c; done <<<"$3"
  [ -n "$w" ] || return 0
  attempt "$1" "$(jq -cn --arg c "$(tail -n 1 <<<"$3")" --arg o "retry --fresh moved the kept work to $w; this record stays" \
    '{card: $c, kind: "fresh", outcome: $o}')"
}
# The line a follow-up's body gets for the record of its parent <card> (of <issue json>): how many fix rounds it holds
# and the last approach, led by a newline; with the pack's privacy.mode public (<mode>), masked as the finding is
# (privmask(), lib/issues.sh), or left out when the check cannot be made. Nothing when the record has no line.
fuattempts() { # <card> <issue json> <parent as the body names it> <privacy mode>
  local f l
  f=$(attemptfile "$(attemptkey "$(jq -r '.number // 0' <<<"$2" 2>/dev/null)" "$1")") && [ -s "$f" ] || return 0
  l=$(jq -Rrs --arg p "$3" '[split("\n")[] | fromjson? | objects] | select(. != [])
    | "Earlier attempts: \(map(select(.kind == "fix")) | length) fix rounds on \($p); last approach: \(map(.approach | select(. != "")) | last // "none recorded" | gsub("\\s+"; " "))"' "$f" 2>/dev/null) && [ -n "$l" ] || return 0
  [ "$4" != public ] || l=$(privmask "$l") || return 0
  printf '\n%s' "$l"
}
