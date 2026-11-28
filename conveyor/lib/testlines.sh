# SPDX-License-Identifier: Apache-2.0
# The lines a test file ran of a file it read, kept with its pass, and the test files a change reaches by them.
# Sourced, never run: by lib/testlist.sh, whose names it reads ($STATE, $TESTCACHE, $HERE).

# $TESTLINES, `<test file>\t<source>\t<blob>\t<lines>\t<gaps>`: of a test file kept in $TESTCACHE, the lines it ran of
# a source in that pass, as its log names them (`TESTRUN lines`: the lines with code that ran, and the lines whose
# end ran, as ranges, `3-7,12`, `-` for none; the blob is the source's content in that run). cachekeep() writes them
# with the pass, in place of the file's earlier ones, and cachereaders() lists the file for a change to that source
# only when the change touches one of those lines (lineshit()). Bug: every page test of the Board reads every script
# of the page, so a change to one function of one script listed each of them (96 test files for card 1798, of which
# none ran a changed line).
TESTLINES=${STATE%/*}/testlines.tsv

# cachekeep()'s part for $TESTLINES, under its lock: of each file kept now (<passes>: `<file>\t<input>...` lines), the
# lines are those its log names in this pass (`TESTRUN lines`, in <log>...), none when its log names none. The kept
# files go to awk as a file: the passes of one step, with their inputs, are longer than one argument, or one variable
# of a program's environment, can be.
lineskeep() { # <passes> <log>...
  local add=$1 ln
  shift
  ln=$(cat "$@" 2>/dev/null | awk -F'\t' 'function bad(p) { return p == "" || p ~ /^\// || p ~ /(^|\/)\.\.(\/|$)/ }
    NR == FNR { keep[$1] = 1; next }
    $1 == "TESTRUN lines" && NF == 6 && ($2 in keep) && !bad($3) && $4 ~ /^[0-9a-f]+$/ && $5 ~ /^[0-9,-]+$/ && $6 ~ /^[0-9,-]+$/ && !seen[$2, $3]++ {
      print $2 "\t" $3 "\t" $4 "\t" $5 "\t" $6 }' <(cut -f1 <<<"$add") -)
  [ -z "$ln" ] && [ ! -s "$TESTLINES" ] || { { [ ! -f "$TESTLINES" ] || awk -F'\t' 'NR == FNR { keep[$1] = 1; next } !($1 in keep)' <(cut -f1 <<<"$add") "$TESTLINES"
      [ -z "$ln" ] || printf '%s\n' "$ln"; } > "$TESTLINES.new" && mv -f "$TESTLINES.new" "$TESTLINES" || rm -f "$TESTLINES.new"; }
}

# The test files whose last pass in $TESTCACHE read a file of <changes> (`git diff --name-status --no-renames` lines),
# one a line, A to Z: one of its inputs; a folder it listed (an input that ends in /) that a file of it is added to or
# deleted from (status A or D); or a path it looked for that a file is added under (status A: the path made a folder).
# Not for a change to the test file itself: the card's own test files run as before, only the cases the change touches
# when it touches only some (owncases()). readersin() adds them to a card's list; rerunsince() drops what the card's last
# run kept of them.
# An engine case file (conveyor/tests/<name>.test.sh) that changes, or is added or deleted, brings no reader that is an
# engine case file: the runner sources every case file to find its cases (conveyor.test.sh: `. tests/*.test.sh`), so
# the trace of each one names every other one, and its folder, as read, and a change to one case file picked every
# engine case file with a traced pass (34 for a 6-line change to review.test.sh, 2026-11-27). Any other reader is
# still picked: spdx.test.sh reads the SPDX line of each tracked file in a run of its own. A case file's own read of
# another (testcountrunner.test.sh's check of function names) cannot be told from the runner's, so it brings no
# reader either; the full test suite, which does not use the cache, still runs it. The changed case file
# itself still runs: it is the card's own test (listcmd()). An engine library file (conveyor/lib/<name>.sh) that
# changes brings no reader that is an engine case file either: every case starts the engine, which sources every
# library file, so each case file's trace names each of them (a change to bugproof.sh picked budgetkept.test.sh,
# which runs none of its functions, 2026-11-27). The test map gives a card the case files of a library file
# (listcmd()). A file the change adds or deletes marks its own folder alone as touched (./ for a file at the top),
# not each folder above it: those folders hold the same names (bug: adding a case file picked each test that
# listed ./ or conveyor/). Given <worktree>, a test file of which $TESTLINES holds the lines it ran of a file the change
# edits is a reader of that file only when the change touches one of those lines (lineshit(), below); without it
# (rerunsince(): a card's own pass is dropped), each reader, as before.
cachereaders() { # <changes> [<worktree>]
  [ -s "$TESTCACHE" ] && [ -n "$1" ] || return 0
  local out m lr=''
  [ -z "${2:-}" ] || [ ! -s "$TESTLINES" ] || lr=$TESTLINES
  # ch: what the change touches; cx: the same, less what an engine case file or library file of it touches, for an
  # engine case file. A file whose only reason is a file the change edits (status M) of which $TESTLINES holds the
  # lines it ran is not printed at once: a line `?\t<file>\t<source>\t<blob>\t<lines>\t<gaps>` for each such source,
  # and lineshit() says whether the change touches one of them.
  out=$(C=$1 awk -F'\t' -v LR="$lr" 'function eng(p) { return p ~ /^conveyor\/tests\/[^\/]+\.test\.sh$/ }
    function src(p) { return eng(p) || p ~ /^conveyor\/lib\/[^\/]+\.sh$/ }
    function mark(p, e) { ch[p] = 1; if (!e) cx[p] = 1 }
    BEGIN { n = split(ENVIRON["C"], l, "\n")
      for (i = 1; i <= n; i++) { if (split(l[i], x, "\t") < 2) continue; e = src(x[2]); mark(x[2], e); if (x[1] ~ /^M/) ed[x[2]] = 1; if (x[1] !~ /^[AD]/) continue
        q = x[2]; if (sub(/[^\/]+$/, "", q) && q == "") q = "./"; mark(q, e) } }
    LR != "" && FILENAME == LR { rec[$1, $2] = $3 "\t" $4 "\t" $5; next }
    { last[$3] = $0 }
    END { for (f in last) { k = split(last[f], a, "\t"); e = eng(f); sure = 0; q = ""
        for (i = 4; i <= k && !sure; i++) {
          own = e ? (a[i] in cx) : (a[i] in ch)
          if (!own && !(a[i] !~ /\/$/ && (e ? ((a[i] "/") in cx) : ((a[i] "/") in ch)))) continue
          if (own && (a[i] in ed) && ((f, a[i]) in rec)) q = q "?\t" f "\t" a[i] "\t" rec[f, a[i]] "\n"; else sure = 1 }
        if (sure) print f; else printf "%s", q } }' ${lr:+"$lr"} "$TESTCACHE")
  m=$(grep $'^?\t' <<<"$out" | cut -f2-)
  { grep -v $'^?\t' <<<"$out"; [ -z "$m" ] || lineshit "$2" "$m"; } | awk NF | LC_ALL=C sort -u
}
# Of <rows> (`<test file>\t<source>\t<blob>\t<lines>\t<gaps>`, $TESTLINES's), the test files whose lines the staged
# change in <worktree> touches (jq/ranlines.jq, which a project's own selector of the changed tests can read too):
# each source is compared, as the change has it, with the blob the test ran. A blob that is gone, or a rule that
# cannot be read, counts as touched: the file is listed, as with no lines on record.
lineshit() { # <worktree> <rows>
  local p b d=''
  while IFS=$'\t' read -r p b; do
    d+="K"$'\t'"$p"$'\t'"$b"$'\n'
    if git -C "$1" cat-file -e "$b" 2>/dev/null; then
      d+=$(diff -U0 <(git -C "$1" cat-file -p "$b" 2>/dev/null) <(git -C "$1" show ":$p" 2>/dev/null) | grep '^@@ ' || :)$'\n'
    else d+='!'$'\n'; fi
  done < <(cut -f2,3 <<<"$2" | LC_ALL=C sort -u)
  jq -Rrn --rawfile d <(printf '%s' "$d") -f "$HERE/jq/ranlines.jq" <<<"$2" 2>/dev/null || cut -f1 <<<"$2"
}
