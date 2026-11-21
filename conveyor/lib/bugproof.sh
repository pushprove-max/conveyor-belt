# SPDX-License-Identifier: Apache-2.0
# The bug-card check (README.md, Bug cards: the new tests fail without the fix): a bug card's new tests run on main's
# code without the fix (bugproof()), and a main-red fix card's proof, main's own failing cases (redproof()). Sourced
# by lib/testrun.sh.
# Tests inside product files (#140): the pack's tests.inline (the schema's default kinds, with the pack's added; one of
# the same name replaces the default's). Of the staged change's added or changed files that are not test files
# (testpaths()), each that a kind's files match, as <path> NUL <kind json> NUL. Fails when the pack cannot be read.
inlinekinds() { # <worktree>
  local t
  packget tests.inline t || return 1
  git -C "$1" diff --cached --name-only --no-renames --diff-filter=AM -z HEAD -- 2>/dev/null | testpaths -vz \
    | jq -jRs --argjson t "$t" --argjson d "$(jq -c '.properties.tests.properties.inline.default' <<<"$SCHEMA_T")" "$GLOBRX"'
      ($d + $t) as $k | split("\u0000")[] | select(. != "") as $f
      | first($k[] | (.files | globsrx) as $r | select($f | test($r))) | ($f, tojson) | . + "\u0000"'
}
# Each line of a file (stdin) as T (in a test block of the kind IS, IE, IH: start, end and has), N (not in one) or S (in
# one, and holding code outside it: before its start or after its end). A block starts at IS's match; with IE
# "braces" it ends where the brackets opened after the start close, or at a ; before any opens; else it ends at IE's
# match. A block none of whose lines match IH (when set) is no test. Brackets inside strings are counted too.
# shellcheck disable=SC2016 # awk's own $0 and fields
INLINEMARKS='BEGIN { s = ENVIRON["IS"]; e = ENVIRON["IE"]; h = ENVIRON["IH"]; br = (e == "braces") }
function shut(last, tail,   i, t) {
  t = (h == "" || hit) ? "T" : "N"; for (i = b; i <= last; i++) c[i] = t
  if (t == "T" && (lead || tail)) { c[b] = (lead ? "S" : c[b]); if (tail) c[last] = "S" }
  inb = 0
}
{ c[NR] = "N"
  if (!inb) {
    if (!match($0, s)) next
    inb = 1; b = NR; hit = 0; d = 0; op = 0
    lead = (substr($0, 1, RSTART - 1) ~ /[^[:space:]]/); rest = substr($0, RSTART + RLENGTH)
  } else rest = $0
  if (h != "" && $0 ~ h) hit = 1
  if (br) {
    for (i = 1; i <= length(rest); i++) {
      ch = substr(rest, i, 1)
      if (ch == "{") { d++; op = 1 } else if (ch == "}") d--
      if ((op && d <= 0) || (ch == ";" && !op)) { t = substr(rest, i + 1); shut(NR, t ~ /[^[:space:]]/ && t !~ /^[[:space:]]*\/\//); next }
    }
  } else if (match(rest, e)) shut(NR, substr(rest, RSTART + RLENGTH) ~ /[^[:space:]]/)
}
END { if (inb) shut(NR, 0); for (i = 1; i <= NR; i++) print c[i] }'
# The staged file <path> of <worktree> with the fix taken out. Each line of main's file (HEAD) and of the staged one is
# marked (INLINEMARKS, by <kind json>). The fix is the diff of main's code lines (N) to the staged code lines; the
# staged file with that diff undone keeps the change's test lines and none of its code. Exit 0 when the change adds or
# changes a test line (T), printing that file; 1 when it changes none (or a file cannot be read); 3, printing nothing,
# when a line it changes is shared by a test block and code (S): the fix cannot be taken out alone.
inlinesplit() { # <worktree> <path> <kind json>
  local w=$1 f=$2 d k=() rc
  mapfile -d '' -t k < <(jq -j '.start, .end, (.has // "") | . + "\u0000"' <<<"$3") && [ ${#k[@]} = 3 ] && d=$(mktemp -d) || return 1
  { git -C "$w" show "HEAD:$f" 2>/dev/null || :; } > "$d/old" && git -C "$w" show ":$f" > "$d/new" 2>/dev/null \
    && IS=${k[0]} IE=${k[1]} IH=${k[2]} awk "$INLINEMARKS" < "$d/old" > "$d/old.m" \
    && IS=${k[0]} IE=${k[1]} IH=${k[2]} awk "$INLINEMARKS" < "$d/new" > "$d/new.m" || { rm -rf "$d"; return 1; }
  # Which kinds of line the change touches: a test line it adds or changes, a shared line it adds, changes or removes.
  # A diff --no-index exits 1 when the files differ, which under pipefail would fail the pipe: only a higher exit does.
  { git diff --no-index --no-color --no-ext-diff -U"$(( $(wc -l < "$d/old") + $(wc -l < "$d/new") + 1 ))" -- "$d/old" "$d/new"; [ $? -le 1 ]; } \
    | awk 'FILENAME == ARGV[1] { o[FNR] = $0; next } FILENAME == ARGV[2] { n[FNR] = $0; next }
      /^@@/ { h = 1; next } !h || /^\\/ { next }
      { t = substr($0, 1, 1) } t == " " { oi++; ni++ } t == "-" { if (o[++oi] == "S") sh = 1 }
      t == "+" { ni++; if (n[ni] == "S") sh = 1; else if (n[ni] == "T") nt++ }
      END { exit sh ? 3 : nt ? 0 : 1 }' "$d/old.m" "$d/new.m" -
  rc=$?
  if [ $rc = 0 ]; then
    awk 'FILENAME == ARGV[1] { m[FNR] = $0; next } m[FNR] == "N"' "$d/old.m" "$d/old" > "$d/old.c"
    awk 'FILENAME == ARGV[1] { m[FNR] = $0; next } m[FNR] == "N"' "$d/new.m" "$d/new" > "$d/new.c"
    # Each hunk of the fix (-U0: staged code lines c to c+n-1 were main's lines, or main's lines go after line c when n
    # is 0) undone in the staged file, its test lines kept where they are.
    { git diff --no-index --no-color --no-ext-diff -U0 -- "$d/old.c" "$d/new.c"; [ $? -le 1 ]; } \
      | awk 'function put(x,   i) { for (i = 1; i <= on[x]; i++) print ol[x, i] }
        FILENAME == ARGV[1] { m[FNR] = $0; next } FILENAME == ARGV[2] { nl[FNR] = $0; nn = FNR; next }
        /^@@/ { split($3, p, ","); h++; hs[h] = substr(p[1], 2) + 0; hd[h] = (p[2] == "" ? 1 : p[2] + 0); next }
        h && /^-/ { ol[h, ++on[h]] = substr($0, 2) }
        END {
          for (x = 1; x <= h; x++) if (hd[x]) { for (j = hs[x]; j < hs[x] + hd[x]; j++) rep[j] = x } else ins[hs[x]] = x
          if (0 in ins) put(ins[0])
          j = 0
          for (i = 1; i <= nn; i++) {
            if (m[i] != "N") { print nl[i]; continue }
            j++
            if (j in rep) { if (!(rep[j] in done)) { done[rep[j]] = 1; put(rep[j]) } } else print nl[i]
            if (j in ins) put(ins[j])
          }
        }' "$d/new.m" "$d/new" - || rc=1
  fi
  rm -rf "$d"; return $rc
}
# The JavaScript text on stdin with its comments (// and /* */, around strings, template literals and regular
# expressions) taken out. Whitespace before a comment goes with it, and a /* */ comment between two tokens leaves one
# space, as it parts them (a/**/b is not ab). Blank lines outside a string go; all else is kept as it is. So two texts
# that differ only in comment text and blank lines give the same output, and text that only looks like a comment (in
# a string, or code between a /* and a */ on lines of their own) stays. Fails (2) on a text it cannot read so (a
# string, comment or expression left open), so a doubt never counts as a comment, and on a comment that holds a line
# break other than the newline that ends its line (a CR, U+2028 or U+2029): JavaScript ends a // comment there, and
# reads a /* */ comment that holds one as a line break (return /*<U+2028>*/ x returns undefined).
uncomment() {
  LC_ALL=C awk -v sq="'" -v ls=$'\xe2\x80\xa8' -v ps=$'\xe2\x80\xa9' '
    function cut() { sub(/[ \t]+$/, "", line) }
    # Whether comment text t holds a line break; with end set, t runs to the end of its line, whose CRLF CR is not one.
    function brk(t, end) { if (end) sub(/\r$/, "", t); return index(t, "\r") || index(t, ls) || index(t, ps) }
    BEGIN { m = "code"; k = 0; lc = ""; w = ""
      split("return typeof instanceof in of new delete void throw case do else yield await", kw, " ")
      for (x in kw) key[kw[x]] = 1 }
    { s = $0; n = length(s); line = ""; esc = 0; i = 1
      while (i <= n) {
        c = substr(s, i, 1); c2 = substr(s, i, 2)
        if (m == "blk") {
          j = index(substr(s, i), "*/"); if (brk(j ? substr(s, i, j - 1) : substr(s, i), !j)) exit 2
          if (!j) { i = n + 1; continue }
          i += j + 1; m = "code"; while (substr(s, i, 1) ~ /[ \t]/) i++; continue
        }
        if (m == "str" || m == "tpl" || m == "re" || m == "cls") {
          if (c == "\\") { line = line c2; if (i == n) esc = 1; i += 2; continue }
          if (m == "tpl" && c2 == "${") { k++; dep[k] = 0; m = "code"; lc = "("; line = line c2; i += 2; continue }
          if (m == "re" && c == "[") m = "cls"; else if (m == "cls" && c == "]") m = "re"
          else if ((m == "str" || m == "tpl") && c == q || m == "re" && c == "/") { m = "code"; lc = "a"; w = "" }
          line = line c; i++; continue
        }
        # m == "code"
        if (c2 == "//") { if (brk(substr(s, i + 2), 1)) exit 2; cut(); i = n + 1; continue }
        if (c2 == "/*") { cut(); if (line != "") line = line " "; m = "blk"; i += 2; continue }
        if (c == "\"" || c == sq || c == "`") { q = c; m = (c == "`") ? "tpl" : "str"; line = line c; i++; continue }
        # A / starts a regular expression unless it follows a value: a name (not a keyword), a number, ) or ].
        if (c == "/" && !(lc ~ /[])]/ || lc ~ /[A-Za-z0-9_$]/ && !(w in key))) { m = "re"; line = line c; i++; continue }
        if (c == "{" && k) dep[k]++
        if (c == "}" && k) { if (!dep[k]) { k--; m = "tpl"; q = "`"; line = line c; i++; continue } dep[k]-- }
        if (c ~ /[A-Za-z0-9_$]/) { w = (lc ~ /[A-Za-z0-9_$]/) ? w c : c; lc = c } else if (c !~ /[ \t\r]/) lc = c
        line = line c; i++
      }
      if (m == "re" || m == "cls" || m == "str" && !esc) exit 2
      if (m == "code" || m == "blk") sub(/[ \t\r]+$/, "", line)
      if (line ~ /^[ \t\r]*$/ && m !~ /^(str|tpl)$/) next
      print line }
    END { if (m != "code") exit 2 }'
}
# Whether the staged change of <worktree> (bugproof()) changes product files (files testpaths() does not take as test
# files), with or without test files, and each product file is a JavaScript file (.js .mjs .cjs .ts .mts .cts) that
# changes only in its comments: its text before and after, its comments taken out (uncomment()), is the same. A file of any other kind, or one whose mode or link
# changes, is not comments only: in a shell or Python file a # in a heredoc or a string cannot be told from a comment
# by its line, a CSS comment can part two tokens of a value or selector, and an HTML comment is a node of the page. Fails when the diff or pack cannot be read.
commentsonly() { # <worktree>
  local ps=() f r om nm ob nb a b
  # A diff or pack that cannot be read adds an empty path, which is no JavaScript file, so the change is not comments
  # only: a list cut short by the failure could else hold only the JavaScript files of a change with others.
  mapfile -d '' -t ps < <(set -o pipefail; git -C "$1" diff --cached --name-only --no-renames -z HEAD -- 2>/dev/null | testpaths -vz || printf '\0')
  [ ${#ps[@]} != 0 ] || return 1
  for f in "${ps[@]}"; do
    case ${f,,} in
      *.js|*.mjs|*.cjs|*.ts|*.mts|*.cts) ;;
      *) return 1 ;;
    esac
    # Its raw diff line: ":<old mode> <new mode> <old blob> <new blob> <status>". Each mode is a plain file's, the same
    # both sides (or 000000 on the side where the file is not, whose text is empty).
    r=$(git -C "$1" diff --cached --raw --no-abbrev --no-renames -z HEAD -- ":(literal)$f" 2>/dev/null | tr '\0' '\n' | head -n 1)
    read -r om nm ob nb _ <<<"${r#:}"
    [[ $om =~ ^(000000|100644|100755)$ && $nm =~ ^(000000|100644|100755)$ ]] || return 1
    [ "$om" = "$nm" ] || [ "$om" = 000000 ] || [ "$nm" = 000000 ] || return 1
    a=''; b=''
    if [[ ! $ob =~ ^0+$ ]]; then a=$(set -o pipefail; git -C "$1" cat-file blob "$ob" | uncomment) || return 1; fi
    if [[ ! $nb =~ ^0+$ ]]; then b=$(set -o pipefail; git -C "$1" cat-file blob "$nb" | uncomment) || return 1; fi
    [ "$a" = "$b" ] || return 1
  done
}
# The bug-card check (card(): a card whose issue has the pack's type label, labels.type, after its build and before its
# review). The test files its staged change adds or changes (paths testpaths() takes for test files: the pack's
# tests.patterns) run on main's code without the
# fix: in a worktree of the commit the card was built on (its HEAD), $CARDS/mainrun/<card>.unfixed, holding those
# files alone, staged, on a test slot, each of them alone with test.fileCommand (tests()); with none set, the check
# does not run and fails with exit 2, its result's first line naming test.fileCommand (NARROW). At least one must
# fail there: a test that passes without the fix does not prove it. A test file that runs past its own time limit
# there (its `# timeout:` line, else testTimeout: testlist.sh bugrun()) is stopped and fails, and the result says it timed out. A product file whose change adds or changes tests
# written inside it (the pack's tests.inline: inlinekinds(), inlinesplit()) is one of those files, staged with its
# test lines changed and the rest of its change (the fix) taken out; when such a test shares a changed line with the
# fix and the change has no other test, the check fails with that reason (SHARED), unrun. Writes the result in
# <worktree>.unfixed, which the review is shown, and fails when the check does not hold: the change adds or changes no
# test file, or no test failed in their run on main (it passed, or only its runner failed it). BUGWHY is the reason,
# which card() gives the build session and the block: "the new tests pass without the fix" (UNFIXED) only when its
# test files ran without the fix; with none found it names the patterns (NOTEST). A run that reports more test files than it was given
# (tests()) is stopped as it runs (watch()): the check fails with exit 2, the result's first line the reason (NARROW),
# as a build session cannot change the pack. A failed run on main
# that gave no result for one of those files (noresult(): no pass and no fail of it) proves nothing either way: it runs
# once more, and when that run gives none either, the result's first line is "the proof run on main gave no result for
# <file>: <the run's last lines>" and the check fails with exit 2 (the card is blocked, as a build session cannot
# repair the runner). A run that cannot be made (no worktree, or the files do not apply) fails
# nothing, as a build session cannot repair it (but for a change with no test file, which fails as before): the result says so. A change to test files alone (a test fix for a
# red main) is not run and fails nothing: with no fix to take out, its tests run on the same code and pass. The result
# says it is test-only, and the review judges its tests. So is a change to product files whose part in them is comments
# only (commentsonly()), with or without test files: no test of a comment can fail without it. The result says it is
# comments only, and the review judges it.
# A change that selects no test of its own (the test map and the links give it no test file: testsel() narrow, on
# main's code with the whole change staged) is proved by the test
# files the issue's `## Done when` section names that are test files of that commit (testpaths()): each named in the
# run's list (CONVEYOR_TEST_RERUN) as `fail<TAB><file>`, so test.fileCommand runs them
# alone, with the fix and then without it. At least one must fail without it, and they must pass with it. When the
# issue names none, the check is skipped and holds: the result and the card's `bugproof` line (result skipped) say why.
# A main-red fix card is not checked so: its proof is main's own failing cases (redproof(), its exits too).
# That selection is read only when the change adds or changes no test file.
bugproof() { # <card> <worktree> <issue json>
  local mwt=$CARDS/mainrun/$1.unfixed fs=() tf=() ins=() iks=() nf=() f k out rc fx held='' sha='' why nr='' sh='' stop='' cn
  rm -f "$2.unfixed"; BUGWHY=$UNFIXED
  # No change at all (an ALREADY-DONE) is not checked: it goes its own way (nochange()).
  git -C "$2" add -A 2>/dev/null && ! git -C "$2" diff --cached --quiet HEAD 2>/dev/null || return 0
  # A main-red fix card (its entry in the main-red record names it) is proved by main's own failing cases (redproof()).
  # Its change that is only the links the engine staged (mainred.sh linksonly()) is no change, as above: card() drops it.
  ! jq -e --arg c "$1" 'any(.reds[]?; .card == $c)' "$MAINRED" >/dev/null 2>&1 || { ! linksonly "$1" "$2" || return 0; redproof "$1" "$2"; return; }
  # A change to test files alone (every changed path, deleted ones too, is a test file: testpaths()) has no fix to take out:
  # its tests would run on the same code and pass, so it is not run. The review is told, and judges the tests.
  # The paths are counted, not tested with grep -q: under pipefail its early exit could fail the pipe and pass a change
  # with a source file as test-only. A diff that cannot be read, or a pack that cannot, counts as a change with one.
  if out=$(git -C "$2" diff --cached --name-only --no-renames -z HEAD -- 2>/dev/null | testpaths -vz | tr -cd '\000' | wc -c) \
    && [ "$((out))" = 0 ]; then
    { echo 'The change is test-only: every file it changes is a test file, so it has no fix to take out, and its tests were not run on main'"'"'s code.'
      echo 'Judge whether each test it changes still checks what it was written to check.'; } > "$2.unfixed"
    return 0
  fi
  # A change to product files whose part in them is comments only (commentsonly()), with or without test files, has no
  # fix to take out either: a comment changes no behaviour, so no test of it can fail on main's code. It is not run; the
  # review is told. Bug: a comment fix with no test file was blocked, as no test could fail without it (#872).
  if commentsonly "$2"; then
    { echo 'The change is comments only in its product files: every line it changes in them is a comment or blank, so it has no fix to take out, and no test of it was run on main'"'"'s code.'
      echo 'Judge whether each changed comment says what the code does, and whether each test it changes, if any, checks what the code does.'; } > "$2.unfixed"
    return 0
  fi
  mapfile -d '' -t tf < <(git -C "$2" diff --cached --name-only --no-renames --diff-filter=AM -z HEAD -- 2>/dev/null | testpaths -z)
  # Product files whose change adds or changes inline tests (inlinekinds(), inlinesplit()) run too, with only their
  # test lines changed: the fix taken out. One whose test shares a changed line with the fix cannot be run so; when the
  # change has no other test to run, that is the reason (SHARED), and no run is made.
  while IFS= read -r -d '' f && IFS= read -r -d '' k; do
    inlinesplit "$2" "$f" "$k" > /dev/null; case $? in 0) ins+=("$f") iks+=("$k") ;; 3) sh=${sh:-$f} ;; esac
  done < <(inlinekinds "$2" 2>/dev/null)
  fs=("${tf[@]}" "${ins[@]}")
  # At most test.cardFiles of them run, as in the card's run (testcap()); the files left out are neither put on main's
  # code nor named as run, and the result says so.
  cn=''
  if testcap "${fs[@]}" && [ "$CAPLEFT" != 0 ]; then
    cn=$CAPNOTE; declare -A kp=(); for f in "${CAPFILES[@]}"; do kp[$f]=1; done
    mapfile -d '' -t tf < <(for f in "${tf[@]}"; do [ -z "${kp[$f]:-}" ] || printf '%s\0' "$f"; done)
    for k in "${!ins[@]}"; do [ -n "${kp[${ins[k]}]:-}" ] || unset 'ins[k]' 'iks[k]'; done; ins=("${ins[@]}") iks=("${iks[@]}")
    fs=("${CAPFILES[@]}")
  fi
  if [ ${#fs[@]} = 0 ] && [ -n "$sh" ]; then
    BUGWHY=${SHARED//'<file>'/"$sh"}; printf '%s.\nIts inline tests were not run on main'"'"'s code.\n' "${BUGWHY^}" > "$2.unfixed"; return 1
  fi
  [ ${#fs[@]} != 0 ] || { [ -n "${TESTGLOBS:-}" ] || names 2>/dev/null; BUGWHY=${NOTEST//'<patterns>'/"${TESTGLOBS:-}"}; }
  # test.fileCommand runs each test file alone, whatever its language, as the list names it; with none set, Conveyor's
  # own runner does (testlist.sh ownrunner()), and with none for a file, the run stops (tests(): <worktree>.stop, NORUNNER).
  if sha=$(git -C "$2" rev-parse -q --verify 'HEAD^{commit}' 2>/dev/null) \
    && out=$({ git worktree remove --force "$mwt" 2>/dev/null; rm -rf "$mwt" "$mwt".*; git worktree prune; mkdir -p "${mwt%/*}" \
      && git worktree add -q --detach "$mwt" "$sha" && deps "$mwt" \
      && { [ ${#tf[@]} = 0 ] || git -C "$2" diff --cached --binary --no-renames HEAD -- "${tf[@]/#/:(literal)}" | git -C "$mwt" apply --index; } \
      && for k in "${!ins[@]}"; do
           mkdir -p "$(dirname "$mwt/${ins[k]}")" && inlinesplit "$2" "${ins[k]}" "${iks[k]}" > "$mwt/${ins[k]}" \
             && git -C "$mwt" add -- ":(literal)${ins[k]}" || exit 1
         done; } 2>&1 < /dev/null); then
    if [ ${#fs[@]} = 0 ]; then
      printf '%s.\n' "${BUGWHY^}" > "$2.unfixed"
    else
      bugmain "$@"
    fi
    # Does the change select any test of its own? Asked only when it has no test file of its own. It selects none
    # when the test map and the links give it no test file (testsel() narrow, on main's code with the whole change
    # staged, as its card's run reads it).
    if [ -z "$held" ] && [ -z "$nr" ] && [ -z "$stop" ] && [ ${#fs[@]} = 0 ] \
      && git -C "$mwt" reset -q --hard && rm -f "$mwt.rerun" \
      && git -C "$2" diff --cached --binary --no-renames HEAD | git -C "$mwt" apply --index 2>/dev/null \
      && out=$(testsel "$mwt" narrow) && [[ $out != *$'\n'* ]]; then
      bugnamed "$@"
    fi
  elif [ ${#fs[@]} = 0 ]; then
    printf '%s.\n' "${BUGWHY^}" > "$2.unfixed"
  else
    printf 'Its test files could not be run on main'"'"'s code at %s: %s\nThe check says nothing of them.\n' "${sha:-a commit that could not be read}" "${out:0:600}" > "$2.unfixed"
    held=1
  fi
  git worktree remove --force "$mwt" 2>/dev/null; rm -rf "$mwt" "$mwt".*; rmdir "${mwt%/*}" 2>/dev/null # the folder, once no card's run is in it
  [ -z "$nr$stop" ] || return 2
  [ -n "$held" ]
}
# The part of bugproof() that runs the change's test files (its fs, tf and ins) on main's code in its worktree (its
# mwt, at its sha) without the fix, and writes the result in <worktree>.unfixed. It is called by bugproof() alone,
# and reads and sets bugproof()'s own locals (rc, stop, held, nr) and the global BUGWHY, which card() reads.
bugmain() { # <card> <worktree> <issue json>
  # A run that reports more test files than it was given is stopped (watch(), tests(): <worktree>.stop), as is one
  # with no test.fileCommand, and the check fails with that reason (exit 2), as a build session cannot change the pack.
  TEST_GIVEN=${#fs[@]} bugrun "$mwt" "${fs[@]}"; rc=$?
  [ ! -s "$mwt.stop" ] || stop=$(<"$mwt.stop")
  [ -n "$stop" ] || ! testfailed "$mwt" "$rc" || held=1
  # A failed run that proved nothing and gave no result for a file it was given (noresult()) says nothing either
  # way: it runs once more, and when that run gives none either the card is blocked with that reason (exit 2).
  if [ -z "$stop" ] && [ -z "$held" ] && nr=$(noresult "$mwt" "$rc" "${fs[@]}"); then
    TEST_GIVEN=${#fs[@]} bugrun "$mwt" "${fs[@]}"; rc=$?
    [ ! -s "$mwt.stop" ] || stop=$(<"$mwt.stop")
    [ -n "$stop" ] || ! testfailed "$mwt" "$rc" || held=1
    [ -z "$stop" ] && [ -z "$held" ] && nr=$(noresult "$mwt" "$rc" "${fs[@]}") || nr=''
  fi
  [ -z "$stop" ] || BUGWHY=$stop
  { [ -z "$stop" ] || printf '%s\n' "$stop"
    [ -z "$nr" ] || printf 'the proof run on main gave no result for %s: %s\n' "$nr" \
      "$(tail -n 5 "$mwt.test" 2>/dev/null | tr -d '\000\r' | sed 's/\x1b\[[0-9;]*m//g' | awk 'NF { sub(/^[ \t]+/, ""); s = s (s == "" ? "" : " / ") $0 } END { print substr(s, 1, 300) }')"
    printf 'Its test files, run on main'"'"'s code at %s without the fix:\n' "$sha"
    [ ${#tf[@]} = 0 ] || printf -- '- %s\n' "${tf[@]}"; [ ${#ins[@]} = 0 ] || printf -- '- %s (its inline tests, with the rest of its change taken out)\n' "${ins[@]}"
    [ -z "$cn" ] || printf '%s\n' "${cn^}"
    if [ -n "$stop" ]; then echo "The run was stopped there, so it proves nothing either way."
    elif [ $rc = 0 ]; then echo "They all passed there: $UNFIXED."
    elif [ -n "$nr" ]; then echo "The run failed there twice (exit $rc), and gave no result for $nr either time, so it proves nothing either way."
    elif [ -z "$held" ]; then echo "The run failed there (exit $rc), but no test failed in it (its runner stopped it): $UNFIXED."
    else echo "The run failed there (exit $rc): at least one fails without the fix, as it should."; latecount "$mwt"; fi
    echo 'The end of that run'"'"'s output:'; echo '```'; tail -n 30 "$mwt.test" 2>/dev/null | tr -d '\000'; echo '```'; } > "$2.unfixed"
}
# The part of bugproof() for a change that selects no test of its own: the test files the issue's Done-when names
# run in bugproof()'s worktree (its mwt, with the whole change staged), with the fix and then without it, and the
# result goes in <worktree>.unfixed. It is called by bugproof() alone, and reads and sets bugproof()'s own locals
# (nf, held, stop, rc, fx, cn) and the global BUGWHY, which card() reads.
bugnamed() { # <card> <worktree> <issue json>
  # The files the issue names are the proof now.
  BUGWHY=$UNFIXED
  mapfile -t nf < <(jq -r '[.body // "" | splits("\r?\n")] as $l
    | ([range($l | length) | select($l[.] | test("^#{1,2}\\s+Done when\\s*$"; "i"))] | first) as $i | select($i != null)
    | $l[($i + 1):] | ((map(test("^#{1,2}\\s")) | index(true)) as $e | if $e == null then . else .[:$e] end)[]
    | scan("[^\\s`\"'"'"'(),;<>]+") | sub("::.*$"; "") | sub("(:[0-9]+(-[0-9]+)?)?[.,:;]*$"; "")' <<<"$3" 2>/dev/null \
    | LC_ALL=C sort -u | testpaths | while IFS= read -r f; do
        [[ $f != *$'\t'* ]] && [ "$(git -C "$mwt" cat-file -t "$sha:$f" 2>/dev/null)" = blob ] && printf '%s\n' "$f"
      done)
  if [ ${#nf[@]} = 0 ]; then
    why='the change selects no test (no test file is linked to the files it touches), and the issue'"'"'s Done-when names no test file'
    printf 'The bug-card check was skipped: %s.\n' "$why" > "$2.unfixed"; held=1
    record "$1" "$(jq -r '.number // 0' <<<"$3")" bugproof skipped "$(jq -cn --arg r "$why" '{reason: $r}')"
  else
    # With the fix (staged above), then without it: the named files alone, each a `fail` line of the list, through
    # test.fileCommand; a run that reports more files than it was given is stopped, as above; at most
    # test.cardFiles of them run (testcap()).
    testcap "${nf[@]}"; nf=("${CAPFILES[@]}"); cn=$CAPNOTE
    TEST_GIVEN=${#nf[@]} bugrun "$mwt" "${nf[@]}"; fx=$?
    [ ! -s "$mwt.stop" ] || stop=$(<"$mwt.stop")
    # Main's code put back fails the check (rc empty): the logs left are those of the run with the fix.
    if [ -n "$stop" ]; then rc=''
    elif git -C "$mwt" reset -q --hard; then TEST_GIVEN=${#nf[@]} bugrun "$mwt" "${nf[@]}"; rc=$?; [ ! -s "$mwt.stop" ] || stop=$(<"$mwt.stop")
    else rc=''; fi
    [ -z "$stop" ] || BUGWHY=$stop
    [ -n "$stop" ] || [ "$fx" != 0 ] || [ -z "$rc" ] || ! testfailed "$mwt" "$rc" || held=1
    { [ -z "$stop" ] || printf '%s\n' "$stop"
      printf 'The change selects no test of its own (no test file is linked to the files it touches), so the test files its issue'"'"'s Done-when names were run alone on main'"'"'s code at %s, with the fix and without it:\n' "$sha"
      printf -- '- %s\n' "${nf[@]}"; [ -z "$cn" ] || printf '%s\n' "${cn^}"
      if [ -n "$stop" ]; then echo "A run was stopped, so it proves nothing either way."
      elif [ "$fx" != 0 ]; then echo "They failed with the fix (exit $fx): $UNFIXED."
      elif [ -z "$rc" ]; then BUGWHY=$NOTBACK; echo "Main's code could not be put back without the fix, so they did not run without it."
      elif [ "$rc" = 0 ]; then echo "They all passed without the fix: $UNFIXED."
      elif [ -z "$held" ]; then echo "The run without the fix failed (exit $rc), but no test failed in it (its runner stopped it): $UNFIXED."
      else echo "They pass with the fix, and the run without it failed (exit $rc): at least one fails without the fix, as it should."; latecount "$mwt"; fi
      echo 'The end of the run without the fix:'; echo '```'; tail -n 30 "$mwt.test" 2>/dev/null | tr -d '\000'; echo '```'; } > "$2.unfixed"
  fi
}
# The bug-card check of a main-red fix card (bugproof(): a card its entry in $MAINRED names, mainred.sh mainred()). Its proof is
# main's own failing cases, not new tests: a right fix for a red main (a rename, a fixture fix) often adds none, or one
# that cannot fail on main's code. Each case its entry holds as it is now runs alone on a test slot, as the test step
# runs a card's failing cases on main (mainred.sh verdicts(), redrun()), in a worktree of the commit the card was built on (its
# HEAD), $CARDS/mainrun/<card>.unfixed: first without the change, then with it staged. Each must fail without the
# change and pass with it. Tests the change adds are not asked for and not run here (the test step runs them). Writes
# the result in <worktree>.unfixed, which the review is shown; its first line is the reason when the check fails.
# Exit 0 when the check holds; 3 when every case passes without the change (main is no longer red for them: card()
# closes the card as already done), or when the pack's test command cannot run them alone (no test.fileCommand, and
# nofilecmd() refuses: nothing shows main red the pack's way); 2 when a case still fails with the change, a case passes without it while another
# fails, a run gave no result for a case, or a run could not be made (card() blocks the card with that first line).
# The output of each run (redkeep()) stays beside the card's kept work after the run's worktree goes: a reason that a
# run gave no result, or could not be made, names that file and quotes its end. A check that holds, or a card that
# closes as already done, keeps none.
redproof() { # <card> <worktree>
  local mwt=$CARDS/mainrun/$1.unfixed cs sha='' out wo='' wi='' rc=2 kw='' ki='' kf='' fc nw
  cs=$(jq -ce --arg c "$1" '[.reds[]? | select(.card == $c) | .cases[] | {name: .case, file, files: [.files[]? | strings], case: (.file as $f
    | if .case == $f then "" elif .case | startswith($f + ": ") then .case[($f | length) + 2:] else .case end)}] | select(. != [])' "$MAINRED" 2>/dev/null) \
    || { echo "the main-red record names no case of this card, so the cases main fails could not be run" > "$2.unfixed"; return 2; }
  if sha=$(git -C "$2" rev-parse -q --verify 'HEAD^{commit}' 2>/dev/null) \
    && out=$({ git worktree remove --force "$mwt" 2>/dev/null; rm -rf "$mwt" "$mwt".*; git worktree prune; mkdir -p "${mwt%/*}" \
      && git worktree add -q --detach "$mwt" "$sha" && deps "$mwt"; } 2>&1 < /dev/null); then
    # With no test.fileCommand and a test command that cannot be given one file (testlist.sh nofilecmd(), #1275), no
    # run shows main red the pack's way (verdicts() marks no case so): the mark has no proof, and the card closes.
    packget test.fileCommand fc 2>/dev/null && [ -z "$fc" ] && ! nw=$(TEST_PACKONLY=1 nofilecmd "$mwt") || nw=''
    [ -n "$nw" ] || { wo=$(redrun "$mwt" "$cs") || wo=''; kw=$(redkeep "$1" "$mwt.test" without); }
    if [ -n "$nw" ]; then
      out="main is not red for $(jq -r '[.[] | "`\(.name)`"] | join(", ")' <<<"$cs") the pack's way: $nw; main is marked red only when that run fails, so the card closes as already done"; rc=3
    elif [ -z "$wo" ] || [ -n "$(rednames none "$wo")" ]; then
      out="the run on main's code at $sha without the change gave no result for $(rednames none "${wo:-$cs}" | sed 's/^$/its cases/'), so it proves nothing either way"; kf=$kw
    elif [ -z "$(rednames fail "$wo")" ]; then
      out="main is no longer red for $(rednames pass "$wo"): they pass on main's code at $sha without the change, so the card closes as already done"; rc=3
    elif [ -n "$(rednames pass "$wo")" ]; then
      out="$(rednames pass "$wo") passes on main's code at $sha without the change (main is no longer red for it), while $(rednames fail "$wo") fails there"
    elif git -C "$2" diff --cached --quiet HEAD 2>/dev/null; then
      out="$(rednames fail "$wo") still fails on main's code at $sha, and there is no change to run them with" # nochange()
    elif ! out=$(git -C "$2" diff --cached --binary --no-renames HEAD | git -C "$mwt" apply --index 2>&1); then
      out="the change could not be applied to main's code at $sha, so the cases did not run with it: ${out:0:400}"
    else
      wi=$(redrun "$mwt" "$cs") || wi=''; ki=$(redkeep "$1" "$mwt.test" with)
      if [ -n "$wi" ] && [ -n "$(rednames fail "$wi")" ]; then out="$(rednames fail "$wi") still fails with the change"
      elif [ -z "$wi" ] || [ -n "$(rednames none "$wi")" ]; then
        out="the run on main's code at $sha with the change gave no result for $(rednames none "${wi:-$cs}" | sed 's/^$/its cases/'), so it proves nothing either way"; kf=$ki
      else out="each case main fails at $sha fails there without the change and passes with it: $(rednames pass "$wi")"; rc=0; fi
    fi
    [ -z "$kf" ] || out+=". The whole output of that run is kept in $kf"
    { printf '%s\n' "${out^}."
      echo 'This card fixes a red main, so its proof is the cases main fails, each run alone on main'"'"'s code without the change and then with it; it need not add a test.'
      if [ -n "$kf" ]; then echo 'The end of that run'"'"'s output:'; echo '```'; tail -n 40 "$kf"; echo '```'
      else echo 'The end of the last run'"'"'s output:'; echo '```'; tail -n 30 "$mwt.test" 2>/dev/null | tr -d '\000'; echo '```'; fi; } > "$2.unfixed"
  elif kf=$(redkeep "$1" <(printf '%s\n' "$out") setup); then
    { printf 'The cases main fails could not be run on main'"'"'s code at %s: its worktree could not be made. The whole output of making it is kept in %s.\n' "${sha:-a commit that could not be read}" "$kf"
      echo 'The end of that output:'; echo '```'; tail -n 40 "$kf"; echo '```'; } > "$2.unfixed"
  else
    printf 'The cases main fails could not be run on main'"'"'s code at %s: %s\n' "${sha:-a commit that could not be read}" "${out:0:600}" > "$2.unfixed"
  fi
  [ $rc = 2 ] || { rm -f "$kw" "$ki" 2>/dev/null; rmdir "$ST/kept/$1" 2>/dev/null; }
  git worktree remove --force "$mwt" 2>/dev/null; rm -rf "$mwt" "$mwt".*; rmdir "${mwt%/*}" 2>/dev/null # the folder, once no card's run is in it
  return $rc
}
# A run's output (<output file>: a run's <worktree>.test) of redproof(), kept beside the card's kept work ($ST/kept/<card>,
# block()) as <card>.redrun-<name>.out, its NUL bytes dropped; an output that cannot be read keeps an empty file. Prints
# its path; fails when it cannot be written.
redkeep() { # <card> <output file> <without|with|setup>
  local f=$ST/kept/$1/$1.redrun-$3.out
  mkdir -p "${f%/*}" 2>/dev/null && { tr -d '\000' < "$2" || :; } 2>/dev/null > "$f" && printf '%s\n' "$f"
}
# The cases of <verdict> in a run's result (mainred.sh redrun()), as `<case>`, joined by ", ".
rednames() { # <verdict> <mainred.sh redrun() output>
  jq -r --arg v "$1" '[.[] | select(.verdict == $v) | "`\(.name)`"] | join(", ")' <<<"$2"
}
# A run of the bug-card check (bugproof()) that is proof: it failed, and a test failed in it. With the runner's logs
# (testlogs()), they must name a file that failed (testfails()); an exit of the runner itself with no test failing (its
# own check refused the run) proves nothing. A command that writes no logs says no more than its exit. A test file
# stopped at its own time limit (testlist.sh bugrun(): <worktree>.late, the run's exit 124) failed: a test that hangs without the
# fix fails without it.
testfailed() { # <worktree> <exit>
  { [ "$2" = 124 ] && [ -s "$1.late" ]; } && return 0
  [ "$2" != 0 ] && { [ -z "$(testlogs "$1")" ] || jq -e '.files != []' <<<"$(testfails "$1.test" "$2")" >/dev/null 2>&1; }
}
