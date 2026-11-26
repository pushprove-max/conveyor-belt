# SPDX-License-Identifier: Apache-2.0
# The parts of a card's test run (tests(), lib/testrun.sh) that say what it runs and keep what it ran: the times it
# records, the test results cache, the cases and runners of the card's list, the bug-card check's run and the run's
# clock, the runner's report and coverage, and the list of what the next run need not run again. Sourced by
# lib/testrun.sh.
# The times of a card's own run (README.md, The test step), recorded and shown; no file is held to a CPU time. A
# runner times each file it runs with a log line
# `TESTRUN sec<TAB><file><TAB><seconds><TAB><CPU seconds>` as the file ends, the last such line of a file counting,
# those of the run before a run again (<worktree>.times, tests()) first.
# Written: the times of each test file the change adds or
# modifies, {file, sec, cpu}, to <worktree>.timed, for its test line (timed); and the CPU seconds of every file the run
# timed, {file: cpu}, to <worktree>.cpus, for its test line (times); and the clock seconds of every file the run
# timed, {file: sec}, to <worktree>.clocks, for its test line
# (clocks: the snapshot's tests part, testspart()), a file timed by the clock only (a runner's report, reported())
# among them. A file the step ran only some cases of (partran()) has none of them: its time is an earlier step's, not
# this one's; it goes in <worktree>.partial, for its test line (partial).
slowtests() { # <worktree>
  local c t x y p
  rm -f "$1.timed" "$1.cpus" "$1.clocks" "$1.partial"
  c=$(git -C "$1" diff --cached --no-renames --name-status -z --diff-filter=AM HEAD 2>/dev/null \
    | jq -cRs 'split("\u0000") | . as $a | [range(0; length - 1; 2) | {key: $a[. + 1], value: $a[.]}] | from_entries') || return 1
  p=$(partran "$1") || return 1; printf '%s\n' "$p" > "$1.partial"
  # The map and the list go to jq as files: as an argument, a run that timed many files passes Linux's 128 KiB limit of one (#344).
  t=$(timed "$1" | jq -c --slurpfile p "$1.partial" '$p[0] as $p | with_entries(select(.key | IN($p[]) | not))') || return 1
  jq -c --slurpfile c <(printf '%s' "$c") '$c[0] as $c | [to_entries[] | select($c[.key] != null) | {file: .key} + .value]' <<<"$t" > "$1.timed" || return 1
  { IFS= read -r x && IFS= read -r y; } < <(jq -c '(with_entries(select(.value.cpu != null)) | map_values(.cpu)), map_values(.sec)' <<<"$t") \
    && printf '%s\n' "$x" > "$1.cpus" && printf '%s\n' "$y" > "$1.clocks"
}
# The files a run in <worktree> timed, {file: {sec, cpu}} (cpu null when the line gives none): its runners'
# `TESTRUN sec` lines, those of the runs before a run after a fix session (<worktree>.oldtimes, tests()) first, then
# those of the run before a run again (<worktree>.times), then those read from the runner's own report
# (<worktree>.reported, reported()), the last line of a file counting: a runner's own line wins. With own, the runs
# before a run after a fix session are left out: the files this step ran.
timed() { # <worktree> [own]
  local l logs=()
  mapfile -t logs < <(testlogs "$1")
  { [ "${2:-}" = own ] || cat "$1.oldtimes" 2>/dev/null; cat "$1.times" "$1.reported" 2>/dev/null; for l in "${logs[@]}"; do printf '\n'; cat "$l" 2>/dev/null; done; } \
    | jq -cRn '[inputs | capture("^TESTRUN sec\t(?<f>[^\t]+)\t(?<s>[0-9]+(\\.[0-9]+)?)(\t(?<c>[0-9]+(\\.[0-9]+)?))?$")
      | {key: .f, value: {sec: (.s | tonumber), cpu: (.c | tonumber? // null)}}] | from_entries'
}
# The CPU seconds, summed, of test files <file>... run alone in <worktree> on a test slot (test.fileCommand), each as its
# runner times it (timed()); nothing when one of them has none. Fails when their run fails: a runner times a failed
# file too. The merge check of an Optimize card runs it (lib/speedproof.sh optproof()).
mergecpu() { # <worktree> <file>...
  printf 'fail\t%s\n' "${@:2}" > "$1.rerun" && tests "$1" test.fileCommand alone > /dev/null 2>&1 || return 1
  timed "$1" 2>/dev/null | jq -r '. as $t | [$ARGS.positional[] | $t[.].cpu?] | if all(.[]; type == "number") then add | . * 1000 | round / 1000 else empty end' \
    --args "${@:2}" 2>/dev/null
}
# The files the step in <worktree> ran some cases of and timed none of, as a JSON list: a `TESTRUN case` line of its
# logs or of the run before a run again (<worktree>.times, tests()) names them, and no `TESTRUN sec` line of this step
# does (timed own): a runner times no file it ran in part. A time of one on record is an earlier step's. The map of
# times goes to jq as a file, as in slowtests().
partran() { # <worktree>
  local o l=()
  o=$(timed "$1" own) || return 1
  mapfile -t l < <(testlogs "$1")
  { cat "$1.times" 2>/dev/null; [ ${#l[@]} = 0 ] || cat "${l[@]}" 2>/dev/null; } \
    | jq -cRn --slurpfile o <(printf '%s' "$o") '$o[0] as $o | [inputs | capture("^TESTRUN case\t(?<f>[^\t]+)\t") | .f | select($o[.] == null)] | unique'
}
# A whole-suite run's files, for the Tests page (the snapshot's tests part, testspart() of lib/testfiles.sh): a line
# for the run appended to $SUITERUNS, {time, how (full: the Board's full test suite, lib/fulltest.sh; release:
# release-prep's, commands/release-prep.sh), sha, files: {<file>: {result: ok or fail (its `-- ok|FAIL <file>` line;
# null with none), sec, cpu (its last `TESTRUN sec` line's; null with none)}}}, read from the times its runner's own
# report gave (<worktree>.reported, reported()), then the logs the run in <worktree> wrote (testlogs()) and its output
# (<worktree>.test), so a runner's own line wins. A run that names no file adds no line.
SUITERUNS=${STATE%/*}/suiteruns.jsonl
suiterec() { # <worktree> <full | release> <commit>
  local logs=()
  mapfile -t logs < <(testlogs "$1")
  { [ ! -f "$1.reported" ] || cat "$1.reported"; cat "${logs[@]}" "$1.test"; } 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' | jq -cRn --arg t "$(clock)" --arg h "$2" --arg s "$3" '
    reduce (inputs | (capture("^TESTRUN sec\t(?<f>[^\t]+)\t(?<s>[0-9]+(\\.[0-9]+)?)(\t(?<c>[0-9]+(\\.[0-9]+)?))?$")
        | {f, v: {sec: (.s | tonumber), cpu: (.c | tonumber? // null)}}),
      (capture("^-- (?<r>ok|FAIL) (?<f>.+)$") | {f, v: {result: (if .r == "ok" then "ok" else "fail" end)}})) as $x ({}; .[$x.f] += $x.v)
    | select(length > 0) | {time: $t, how: $h, sha: $s, files: map_values({result: null, sec: null, cpu: null} + .)}' >> "$SUITERUNS" 2>/dev/null
}
# Its test line's part: {timed: <worktree>.timed} when the run timed a test file the change adds or modifies,
# {times: <worktree>.cpus, clocks: <worktree>.clocks} when it timed any file (times is {} when each was timed by the
# clock only), and carriedrec()'s part, its partial list the one slowtests() saved (<worktree>.partial): a landing
# batch that runs no case (norun(), lib/claim.sh) removes the logs partran() reads before this line is written, else {}.
slowrec() { # <worktree>
  jq -cn --slurpfile t "$1.timed" --slurpfile c "$1.cpus" --slurpfile k "$1.clocks" --slurpfile o <(carriedrec "$1" "$1.partial") '(if $t[0] | length > 0 then {timed: $t[0]} else {} end)
    + (if ($c[0] | length > 0) or ($k[0] | length > 0) then {times: $c[0], clocks: $k[0]} else {} end)
    + $o[0]' 2>/dev/null || echo '{}'
}
# A card's test line's part, a passing (slowrec()) or a failed one (cardfailed(), lib/cardland.sh), for the files
# whose time on record is not this step's: {carried: [file]} for those its run kept as passed and did not run, though a
# run before timed them (<worktree>.oldfiles, tests()), their times on the line the earlier run's; and {partial: [file]}
# for those it ran some cases of and timed none of (partran(), or the list <partial file> holds when given). Else {}.
# The Tests page and its judge date a carried time by the latest earlier step that ran the file whole (HISTFROM,
# lib/testfiles.sh): a failed step that ran one case of it is not one, so its line names the file partial too.
carriedrec() { # <worktree> [<partial file>]
  local p
  if [ -n "${2:-}" ]; then p=$(jq -c 'if type == "array" then . else [] end' "$2" 2>/dev/null) || p='[]'
  else p=$(partran "$1" 2>/dev/null) || p='[]'; fi
  { jq -c 'if type == "array" and length > 0 then {carried: .} else {} end' "$1.oldfiles" 2>/dev/null || echo '{}'; } \
    | jq -c --slurpfile p <(printf '%s' "$p") '. + (if $p[0] | length > 0 then {partial: $p[0]} else {} end)' 2>/dev/null || echo '{}'
}
# The test results cache (README.md, Test file times: The test results cache; the owner, 2026-11-14): each test file a run passed whole,
# with the inputs its command's log named for it (`TESTRUN inputs<TAB><file><TAB><input>...`), one a line in
# $TESTCACHE, `<hash>\t<file>\t<input>...` (cachekeep()), the hash of the file's and its inputs' contents
# (cachesums()). A later run, of any card or the whole test on main, keeps off a file whose hash in its worktree is a
# kept one (cacheoff()). A file its log gives no inputs line for is never kept, so never kept off. The last
# TESTCACHE_KEEP lines are kept; one writer at a time, under a lock of its own.
TESTCACHE=${STATE%/*}/testcache.tsv TESTCACHE_KEEP=5000
# Of lines `<file>\t<input>...` on stdin, each as `<hash>\t<the line>`: the hash of the line's paths, in its order,
# each with the hash of its content in the worktree and whether it can run (a path that is no file there counts as
# missing), by two git calls. A symbolic link counts as the path it names, not the file it leads to (#1619): a test
# can read the link itself, and a link made to lead elsewhere changes that. A file whose content stays the same but
# that can run, or no longer can, changes it too (#1619): a test can run it. A path that is a folder there (one a test
# looked for and did not find, made a folder since) counts as a folder, not as missing (#1619). A folder (a path that
# ends in /, ./ for the worktree's root) counts as the names of the tracked files and folders directly in it, each
# folder's name with a / after it (#1619): a test that listed it reads a change that adds a file there or deletes one,
# or that makes a file there a folder of the same name.
cachesums() { # <worktree>
  local d rc=0 p
  d=$(mktemp -d) || return 1
  cat > "$d/lines"
  tr '\t' '\n' < "$d/lines" | sort -u > "$d/all"
  : > "$d/paths"; : > "$d/modes"; : > "$d/links"
  while IFS= read -r p; do
    [[ $p != */ ]] || continue
    if [ -L "$1/$p" ]; then printf '%s\tlink %s\n' "$p" "$(readlink "$1/$p")" >> "$d/links"
    elif [ -f "$1/$p" ]; then printf '%s\n' "$p" >> "$d/paths"; if [ -x "$1/$p" ]; then echo 100755; else echo 100644; fi >> "$d/modes"
    elif [ -d "$1/$p" ]; then printf '%s\tfolder\n' "$p" >> "$d/links"; fi
  done < "$d/all"
  grep '/$' "$d/all" > "$d/dirs" || :
  : > "$d/dirsums"
  [ ! -s "$d/dirs" ] || { git -C "$1" -c core.quotePath=false ls-files | awk -v d="$d" 'FILENAME == D { at[$0] = ++n; next }
      { m = split($0, p, "/"); q = "./"; for (j = 1; j <= m; j++) { e = p[j] (j < m ? "/" : ""); if ((q in at) && !((q, e) in s)) { s[q, e] = 1; ls[q] = ls[q] e "\n" }; q = (j == 1 ? "" : q) p[j] "/" } }
      END { for (k in at) { f = d "/f" at[k]; printf "%s", ls[k] > f; close(f); print k "\t" f } }' D="$d/dirs" "$d/dirs" - > "$d/dirmap" \
    && cut -f2 "$d/dirmap" | git -C "$1" hash-object --no-filters --stdin-paths | paste <(cut -f1 "$d/dirmap") - > "$d/dirsums"; } || rc=1
  [ $rc = 0 ] && { git -C "$1" hash-object --no-filters --stdin-paths < "$d/paths" > "$d/sums" \
    && paste "$d/paths" <(paste -d' ' "$d/modes" "$d/sums") | cat - "$d/links" "$d/dirsums" > "$d/blobs" \
    && awk -F'\t' -v d="$d" 'FILENAME != L { b[$1] = $2; next }
      { f = d "/e" FNR; for (i = 1; i <= NF; i++) printf "%s\t%s\n", $i, ($i in b ? b[$i] : "-") > f; close(f); print f }' \
      L="$d/lines" "$d/blobs" "$d/lines" > "$d/entries" \
    && git -C "$1" hash-object --no-filters --stdin-paths < "$d/entries" > "$d/hashes" && paste "$d/hashes" "$d/lines"; } || rc=1
  rm -rf "$d"; return $rc
}
# After each run of the command (tests()), each file it passed whole, with the inputs its log names, into $TESTCACHE: a
# file its log ends `-- ok` that no `-- FAIL` line, no `TESTRUN case` line (a run of some of its cases: but for an
# engine case file whose case lines name every `t_<case>() {` case it holds, run whole, #1619) and no `ok`, `fail` or
# `off` line of the list the run was given (some of its cases kept or left out) names. A file a path of whose line is
# absolute or climbs out of the worktree (`..`) is not kept.
cachekeep() { # <worktree>
  local l=() add sums lock r=/dev/null cs
  mapfile -t l < <(testlogs "$1"); [ ${#l[@]} -gt 0 ] && grep -qh $'^TESTRUN inputs\t' "${l[@]}" 2>/dev/null || return 0
  [ ! -f "$1.rerun" ] || r=$1.rerun
  # Each case each file with an inputs line holds, `<file>\t<case>`.
  cs=$(cat "${l[@]}" 2>/dev/null | awk -F'\t' '$1 == "TESTRUN inputs" { print $2 }' | sort -u | while IFS= read -r f; do
    [ ! -f "$1/$f" ] || sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$1/$f" | awk -v f="$f" '{ print f "\t" $0 }'; done | sort -u)
  add=$(C=$cs awk -F'\t' -v L="$r" 'function bad(p) { return p == "" || p ~ /^\// || p ~ /(^|\/)\.\.(\/|$)/ }
    BEGIN { n = split(ENVIRON["C"], x, "\n"); for (i = 1; i <= n; i++) if (split(x[i], y, "\t") == 2) { all[y[1], y[2]] = 1; na[y[1]]++ } }
    FILENAME == L { if ($1 == "ok" || $1 == "fail" || $1 == "off") part[$2] = 1; next }
    /^-- ok / { ok[substr($0, 7)] = 1; next }
    /^-- FAIL / { part[substr($0, 9)] = 1; next }
    $1 == "TESTRUN case" { hc[$2] = 1; if (!(($2, $3) in all)) part[$2] = 1; else if (!(($2, $3) in got)) { got[$2, $3] = 1; ng[$2]++ }; next }
    $1 == "TESTRUN inputs" { if (bad($2)) next; seen[$2] = 1; for (i = 3; i <= NF; i++) { if (bad($i)) part[$2] = 1; inp[$2] = inp[$2] "\t" $i } }
    END { for (f in seen) if ((f in ok) && !(f in part) && (!(f in hc) || ng[f] == na[f])) print f inp[f] }' "$r" "${l[@]}")
  [ -n "$add" ] || return 0
  sums=$(printf '%s\n' "$add" | cachesums "$1") || return 1
  { exec {lock}>>"$TESTCACHE.lock"; } 2>/dev/null || return 1
  flock "$lock" || { exec {lock}>&-; return 1; }
  # Each hash once, at its last place; the last TESTCACHE_KEEP lines.
  { cat "$TESTCACHE" 2>/dev/null; printf '%s\n' "$sums"; } | awk -F'\t' 'length { a[++n] = $0; k[n] = $1; at[$1] = n }
    END { for (i = 1; i <= n; i++) if (at[k[i]] == i) print a[i] }' | tail -n "$TESTCACHE_KEEP" > "$TESTCACHE.new" \
    && mv -f "$TESTCACHE.new" "$TESTCACHE" || rm -f "$TESTCACHE.new"
  exec {lock}>&-
}
# The files of $TESTCACHE whose hash in the worktree is a kept one, one a line: each passed before with the inputs it
# has there (cacheoff(); mainred.sh verdicts(): its inputs did not change since that pass).
cachehits() { # <worktree>
  [ -s "$TESTCACHE" ] || return 0
  cut -f2- "$TESTCACHE" | sort -u | cachesums "$1" | awk -F'\t' 'NR == FNR { k[$1] = 1; next } $1 in k { print $2 }' "$TESTCACHE" - | sort -u
}
# A run (tests(): a card's, and the whole test on main) is told to keep off each file of $TESTCACHE whose hash in its
# worktree is a kept one: a `pass` and an `off` line for it in its list (the off line keeps it off though
# a `changed` or `main` line selects it, its inputs being the same), unless the list names failed cases of it. Prints
# each such file's line for the run's log, `TESTRUN why<TAB><file><TAB>passed before with the same inputs`: of a card's
# run, only for a file of its list (TEST_FILES), so its log names no test it never selected as reused. Each other
# file of the card's list (TEST_FILES, listcmd()) that its list does not keep as passed or keep off whole gets a line
# that says why no pass of it is used (#1619): its inputs changed since the last pass on record, or it has no pass on
# record with its inputs (no $TESTCACHE yet, or its runner names none).
cacheoff() { # <worktree>
  local f m add=''
  m=$(cachehits "$1") || return 0
  while IFS= read -r f; do
    [ -n "$f" ] && ! grep -qxF -- "$f" <<<"$m" && ! grep -qxF -e "pass"$'\t'"$f" -e "off"$'\t'"$f" "$1.rerun" 2>/dev/null || continue
    if cut -f2 "$TESTCACHE" 2>/dev/null | grep -qxF -- "$f"; then printf 'TESTRUN why\t%s\tits inputs changed since its last pass, so the test runs again\n' "$f"
    else printf 'TESTRUN why\t%s\tno pass of it is on record with the files it reads, so the test runs\n' "$f"; fi
  done <<<"${TEST_FILES:-}"
  [ -n "$m" ] || return 0
  while IFS= read -r f; do
    grep -qxF "pass"$'\t'"$f" "$1.rerun" 2>/dev/null || add+="pass"$'\t'"$f"$'\n'
    grep -qxF "off"$'\t'"$f" "$1.rerun" 2>/dev/null || add+="off"$'\t'"$f"$'\n'
    [ -z "${TEST_FILES:-}" ] || grep -qxF -- "$f" <<<"$TEST_FILES" || continue
    printf 'TESTRUN why\t%s\tpassed before with the same inputs\n' "$f"
  done < <(cat "$1.rerun" 2>/dev/null | M=$m awk -F'\t' 'BEGIN { n = split(ENVIRON["M"], a, "\n"); for (i = 1; i <= n; i++) w[a[i]] = 1 }
    $1 == "fail" { delete w[$2] } END { for (f in w) print f }' | sort)
  [ -z "$add" ] || printf '%s' "$add" >> "$1.rerun"
}
# listcmd()'s list fs with each test file added, run whole, whose last pass in $TESTCACHE read a file the staged change
# in <worktree> touches (#1619): one of its inputs, a folder it listed (an input that ends in /) that the change adds a
# file to or deletes one from, or a path it looked for that the change adds a file under (cachereaders()). Only files
# still there. The test map and the links still
# give the tests that have no pass on record; cacheoff() keeps off a file whose inputs are the same as at a pass. One
# already on the list with only some of its cases (TEST_CASES) runs whole: a case it does not name can read that file.
# READADD: the files it added; READLINKS: how many of them are linked files (lk, listcmd()'s) the cap left out;
# READWHOLE: set when it made one run whole (listcmd() counts these in its note).
# shellcheck disable=SC2034,SC2154 # READWHOLE is read by listcmd() (lib/testrun.sh), and lk is its own
readersin() { # <worktree>
  local f c
  READADD=(); READWHOLE=''; READLINKS=0
  [ -s "$TESTCACHE" ] && c=$(git -C "$1" -c core.quotePath=false diff --cached --name-status --no-renames HEAD -- 2>/dev/null) && [ -n "$c" ] || return 0
  while IFS= read -r f; do
    [ -f "$1/$f" ] || continue
    if [ ${#fs[@]} != 0 ] && printf '%s\n' "${fs[@]}" | grep -qxF -- "$f"; then
      cut -f1 <<<"${TEST_CASES:-}" | grep -qxF -- "$f" || continue
      TEST_CASES=$(awk -F'\t' -v f="$f" '$1 != f' <<<"$TEST_CASES"); TEST_CASES=${TEST_CASES:+$TEST_CASES$'\n'}; READWHOLE=1
    else fs+=("$f"); READADD+=("$f"); [ ${#lk[@]} = 0 ] || ! printf '%s\n' "${lk[@]}" | grep -qxF -- "$f" || READLINKS=$((READLINKS + 1)); fi
  done < <(cachereaders "$c")
  runnersout
}
# The test files whose last pass in $TESTCACHE read a file of <changes> (`git diff --name-status --no-renames` lines),
# one a line, A to Z: one of its inputs; a folder it listed (an input that ends in /) that a file of it is added to or
# deleted from (status A or D); or a path it looked for that a file is added under (status A: the path made a folder).
# Not for a change to the test file itself: the card's own test files run as before, only the cases the change touches
# when it touches only some (owncases()). readersin() adds them to a card's list; rerunsince() drops what the card's last
# run kept of them.
cachereaders() { # <changes>
  [ -s "$TESTCACHE" ] && [ -n "$1" ] || return 0
  C=$1 awk -F'\t' 'BEGIN { n = split(ENVIRON["C"], l, "\n")
      for (i = 1; i <= n; i++) { if (split(l[i], x, "\t") < 2) continue; ch[x[2]] = 1; if (x[1] !~ /^[AD]/) continue
        ch["./"] = 1; m = split(x[2], p, "/"); q = ""; for (j = 1; j < m; j++) { q = q p[j] "/"; ch[q] = 1 } } }
    { last[$2] = $0 }
    END { for (f in last) { k = split(last[f], a, "\t"); for (i = 3; i <= k; i++) if ((a[i] in ch) || (a[i] !~ /\/$/ && (a[i] "/") in ch)) { print f; break } } }' "$TESTCACHE" | LC_ALL=C sort
}
# The cases of the test file <file> that the staged change in <worktree> adds or changes (listcmd(), #414), A to Z, one
# a line: by the case scan (CASESCAN, lib/testfiles.sh) of main's file (HEAD) and of the staged one, each case of the
# staged file that holds a line the change adds, or whose case in main's file holds a line the change takes out. A
# blank line is in no case and changes none. It fails, and the file runs whole, for a file main does not have (a new
# test file), a line the change adds or takes out that is not blank and is in no case (a helper or setup outside any
# case: the file's shared part), a case whose end the scan cannot find, or a change that leaves no case to run (it
# only takes cases out).
owncases() { # <worktree> <file>
  local c
  git -C "$1" cat-file -e "HEAD:$2" 2>/dev/null || return 1
  c=$({ git -C "$1" show "HEAD:$2" | awk -v q="'" "$CASESCAN" | sed 's/^/a\t/'
    git -C "$1" show ":$2" | awk -v q="'" "$CASESCAN" | sed 's/^/b\t/'
    git -C "$1" diff --cached -U0 --no-renames --no-color --no-ext-diff --no-textconv HEAD -- "$2" | sed 's/^/d\t/'; } 2>/dev/null | awk -F'\t' '
    # The line x of side s (a: the file at HEAD, b: the staged one) that the change takes out or adds, l.
    function at(s, x, l,   i, k) {
      if (substr(l, 2) ~ /^[ \t]*$/) return
      for (i = 1; i <= n[s]; i++) { k = s SUBSEP i; if (lo[k] <= x && x <= hi[k]) { if (nm[k] in has) hit[nm[k]] = 1; return } }
      whole = 1
    }
    $1 != "d" { if ($5 == 0) whole = 1; k = $1 SUBSEP (++n[$1]); nm[k] = $3; lo[k] = $4 + 0; hi[k] = $5 + 0; if ($1 == "b") has[$3] = 1; next }
    { l = substr($0, 3) }
    l ~ /^@@ / { split(l, h, " "); split(substr(h[2], 2), o, ","); split(substr(h[3], 2), w, ","); ol = o[1] + 0; nl = w[1] + 0; ih = 1; next }
    !ih { next }
    l ~ /^-/ { at("a", ol++, l); next }
    l ~ /^\+/ { at("b", nl++, l); next }
    END { if (whole || !ih) exit 1; for (c in hit) { print c; m++ }; exit m ? 0 : 1 }') || return 1
  LC_ALL=C sort <<<"$c"
}
# Whether <file>, a test file of the card's own change that its run again shares with main's change (SHAREDRUN:
# listcmd()), keeps the cases the change adds or changes (owncases()), not running whole: when the pack sets
# test.changed, no other of <the card's test files> links to it (.conveyor/test-links.json) and <worktree>.rerun does not
# name it failed with no case (unshare() kept its pass). The command runs of main's change only the cases both changes
# select, which are among those (#1591). Bug (#1591): its cases were dropped, so the command ran every case of the file.
sharedkeep() { # <worktree> <file> <the card's test files>...
  local w=$1 f=$2 tc=''
  shift 2
  grep -qxF -- "$f" <<<"${SHAREDRUN:-}" && packget test.changed tc 2>/dev/null && [ -n "$tc" ] \
    && ! jq -e --arg f "$f" '. as $m | [$ARGS.positional[] as $k | select($k != $f) | $m[$k][]? | select(. == $f)] != []' \
      --args "$@" < "$w/.conveyor/test-links.json" >/dev/null 2>&1 \
    && ! awk -F'\t' -v f="$f" '$1 == "fail" && $2 == f && $3 == "" { x = 1 } END { exit !x }' "$w.rerun" 2>/dev/null
}
# Why <command> cannot be given a list of test files in the form test.list <form> names (the run before a push,
# pushtests(), lib/push.sh): no test.list, none, placeholder with no `{files}` in the command, or args with a command
# that already names the test files its runner runs (testrunner()). Nothing when it can (runner: pushtests() says).
listwhy() { # <worktree> <command> <form>
  local s
  if [ -z "$3" ]; then echo 'test.list is not set, so the test command takes no list'
  elif [ "$3" = none ]; then echo 'test.list is none: the test command takes no list'
  elif [ "$3" = placeholder ] && [[ $2 != *'{files}'* ]]; then echo 'test.list is placeholder, and test.command has no {files}'
  elif [ "$3" = args ] && s=$(testrunner "$2" "$1") && [[ $s == named* ]]; then
    echo "test.list is args, and test.command already names the tests it runs (${s##* }): use placeholder"
  fi
}
# The reason a card stops at its test step, or its bug-card check fails (NARROW), with <why>; with bare, without the
# setting that fixes it (the part after its first `;`).
narrowstop() { # <why> [bare]
  local t=$NARROW
  [ -z "${2:-}" ] || t=${t%%;*}
  printf '%s\n' "${t//'<why>'/"$1"}"
}
# The pack's suite runners (SUITERUNNERS, runnerfiles() in lib/prompts.sh) that the list <file> (CONVEYOR_TEST_RERUN)
# names on a `fail` or `shared` line, a leading ./ taken off, one a line; each such line is taken off the list (#382:
# a runner run as a card's test runs the whole suite). Prints nothing, and leaves the list as it is, when it names none.
runnersoff() { # <list file>
  local rs
  [ -s "$1" ] || return 0
  names > /dev/null 2>&1 || :
  [ -n "${SUITERUNNERS:-}" ] || return 0
  rs=$(awk -F'\t' '$1 == "fail" || $1 == "shared" { sub(/^\.\//, "", $2); print $2 }' "$1" | grep -xF -f <(printf '%s\n' "$SUITERUNNERS") | sort -u) || return 0
  R=$rs awk -F'\t' 'BEGIN { n = split(ENVIRON["R"], a, "\n"); for (i = 1; i <= n; i++) r[a[i]] = 1 }
    { f = $2; sub(/^\.\//, "", f) } ($1 == "fail" || $1 == "shared") && (f in r) { next } { print }' "$1" > "$1.new" && mv -f "$1.new" "$1"
  printf '%s\n' "$rs"
}
# listcmd()'s list fs with each suite runner (SUITERUNNERS) on it taken off, a leading ./ taken off each path; adds
# each one taken off to RUNOFF (#382).
runnersout() {
  local x
  [ ${#fs[@]} != 0 ] && [ -n "${SUITERUNNERS:-}" ] || return 0
  x=$(printf '%s\n' "${fs[@]#./}" | grep -xF -f <(printf '%s\n' "$SUITERUNNERS") | sort -u) || return 0
  mapfile -t fs < <(printf '%s\n' "${fs[@]#./}" | grep -vxF -f <(printf '%s\n' "$x"))
  RUNOFF=$(printf '%s\n' "${RUNOFF:-}" "$x" | grep . | sort -u)
}
# The output line of each runner <paths> (one a line) names, taken off a card's list (runnersoff(), listcmd()).
runnernote() { # <paths>
  local x; while IFS= read -r x; do [ -z "$x" ] || echo "conveyor: $x is left off the card's list: $RUNNERFIX"; done <<<"$1"
}
# The command a run of the test files <file>... in <worktree> gives each of them (filecmd()) when the pack sets no
# test.fileCommand (tests(), listcmd(), mainred.sh repairproof()): Conveyor's own runner, lib/filerun.sh, which runs a file with
# its language's runner from its package. Fails when that has no runner for one of them, printing the reason a run
# stops with (NORUNNER), which names the first such file.
ownrunner() { # <worktree> <file>...
  local w=$1 f r why; shift
  for f; do
    r=$(cd "$w" && bash "$HERE/lib/filerun.sh" --which "$f" 2>&1) && continue
    why=${NORUNNER//'<file>'/"$f"}; printf '%s\n' "${why//'<reason>'/"$r"}"; return 1
  done
  printf 'bash %q\n' "$HERE/lib/filerun.sh"
}
# The command tests() gives each test file when the pack sets no test.fileCommand: ownrunner()'s, except on a run that
# checks whether main fails a file (TEST_PACKONLY set: mainred.sh verdicts(), redrun(); #1275). Such a run marks main
# red, so it runs the file the way the pack's test command does: test.command given the file as test.list says
# (args: its path at the end; placeholder: in place of `{files}`; env: in CONVEYOR_TEST_FILES), in the shape
# filecmd() gives it the path. Conveyor's own runner is not the pack's way (a TypeScript file it gives node without
# the project's loader fails to load). Fails, printing why, when the test command cannot be given one file
# (listwhy(), or test.list runner).
nofilecmd() { # <worktree> <file>...
  local tc lm why
  [ -n "${TEST_PACKONLY:-}" ] || { ownrunner "$@"; return; }
  packget test.command tc test.list lm 2>/dev/null || { echo 'the pack could not be read'; return 1; }
  why=$(listwhy "$1" "$tc" "$lm")
  [ -n "$why" ] || [ "$lm" != runner ] || why='test.list is runner, so the test command reads the whole list itself'
  [ -n "$why" ] || [ -n "$tc" ] || why='the pack sets no test command'
  [ -z "$why" ] || { printf 'the pack sets no test.fileCommand, and its test command cannot be given one test file (%s), so the file did not run on main the way the pack runs it\n' "$why"; return 1; }
  case $lm in
    args) printf '%s\n' "$tc" ;;
    placeholder) printf 'packfile() {\n%s\n}; packfile\n' "${tc//'{files}'/'"$1"'}" ;;
    env) printf 'packfile() {\nexport CONVEYOR_TEST_FILES=$1\n%s\n}; packfile\n' "$tc" ;;
    *) printf 'the pack sets no test.fileCommand, and its test.list, %s, is no form a test file can be given in\n' "$lm"; return 1 ;;
  esac
}
# A run file by file (filecmd(), lib/testrun.sh) whose invocations before the k-th reported more than k - 1 test
# files: one ran files it was not given, even when it ended, and the next began, between two looks of watch()
# (lib/session.sh, for a run given TEST_GIVEN files: tests() and bugrun() below). What they reported is counted
# (testprogress()) from the logs as they were when the k-th began: its `files` log up to that `== <file>` line, each
# other log up to the size its `=@ <bytes> <log>` line gives. Each k after the first and after <read> (how many a
# call before read) is read once. The first that is over writes <worktree>.wide, the count, then the file that ran
# just before it on a second line; fails when none is, and prints how many it has read.
# A card's run starts its files side by side (fileeach() side, lib/fileeach.sh), so a file can begin before the one
# begun ahead of it reports it, and a file whose run ran another file of the list is over at no begin. A runner names
# a file once a run of it, in one of its logs (as testfails() and suiteprog() read them): a file the logs other than
# `files` name (`-- ok|FAIL <file>`), all of them together, more times than the run began it (its `== <file>` lines in
# `files`) was run by another file's run too, whether that run wrote to the same log or to one of its own. That writes
# <worktree>.wide too: how many times the logs named it, the file, then `begun <n>`, the times the run began it.
wideeach() { # <worktree> [read]
  local lg=$1.testlog/files k=0 line pre='' fs=() i n d prev='' rc=1 ls=()
  [ -s "$lg" ] || { echo "${2:-0}"; return 1; }
  while IFS= read -r line; do
    case $line in
      '=@ '*) line=${line#=@ }; fs+=("${line%% *}" "${line#* }"); continue ;;
      '== '*) k=$((k + 1))
        if [ "$k" -gt 1 ] && [ "$k" -gt "${2:-0}" ] && d=$(mktemp -d 2>/dev/null); then
          printf '%s' "$pre" > "$d/files"
          for ((i = 0; i < ${#fs[@]}; i += 2)); do [[ ${fs[i]} =~ ^[0-9]+$ ]] && [ "${fs[i + 1]}" != files ] && head -c "${fs[i]}" "$1.testlog/${fs[i + 1]}" > "$d/${fs[i + 1]}" 2>/dev/null; done
          n=$(testprogress /dev/null "$d"/* | jq -r '.run + (.over // 0)' 2>/dev/null); rm -rf "$d"
          [[ $n =~ ^[0-9]+$ ]] && [ "$n" -gt $((k - 1)) ] && printf '%s\n%s\n' "$n" "$prev" > "$1.wide" && rc=0 && break
        fi
        fs=(); prev=${line#== } ;;
    esac
    pre+=$line$'\n'
  done < "$lg"
  [ $rc = 0 ] || mapfile -t ls < <(find "$1.testlog" -maxdepth 1 -type f ! -name files 2>/dev/null | sort)
  if [ ${#ls[@]} -gt 0 ] && line=$(awk 'FNR == 1 { n++ } { gsub(/\033\[[0-9;]*m/, "") }
      n == 1 { if (sub(/^== +/, "")) { sub(/[ \r]+$/, ""); if ($0 != "") b[$0]++ }; next }
      /^-- (ok|FAIL) / { k = $0; sub(/^-- (ok|FAIL) +/, "", k); sub(/[ \r]+$/, "", k); while (sub(/ +[0-9][0-9.]*m?s$/, "", k)) ;
        if ((k in b) && ++c[k] > b[k]) { printf "%d\n%s\nbegun %d\n", c[k], k, b[k]; exit } }' "$lg" "${ls[@]}" 2>/dev/null) && [ -n "$line" ]; then
    printf '%s\n' "$line" > "$1.wide"; rc=0
  fi
  [ $rc = 0 ] || echo "$k"; return $rc
}
# One run of the bug-card check in <worktree>: the files <file>... each alone through test.fileCommand, each a `fail`
# line of the run's list (CONVEYOR_TEST_RERUN). A file that runs past its own time limit (its `# timeout:` line:
# filecmd()) is stopped and fails, and the output says so; one still running when the run's own limit (the
# testTimeout setting) stops the run is named by the run's clock (testclock(), TEST_LATE), and the output ends with a
# line saying the run's limit stopped it. Either is named in <worktree>.late, `<seconds><TAB><file>`, with the run's
# limit after a second tab for the second; bugproof.sh testfailed() counts it as failing.
bugrun() { # <worktree> <file>...
  local w=$1 rc TEST_LATE=1; shift
  rm -f "$w.late"
  printf 'fail\t%s\n' "$@" > "$w.rerun" && tests "$w" test.fileCommand alone; rc=$?
  if [ -s "$w.late" ]; then latesaid "$w" >> "$w.test"
  else sed -n 's/^conveyor: \(.*\) timed out: it ran past its time limit, \([0-9]*\) s, and it was stopped there\(; the limit is .*\)\{0,1\}$/\2\t\1/p' "$w.test" 2>/dev/null | head -n 1 > "$w.late"
    [ -s "$w.late" ] || rm -f "$w.late"; fi
  return $rc
}
# The line that says a file of the bug-card check's run timed out (<worktree>.late, testclock()).
latesaid() { # <worktree>
  local n f r
  [ -s "$1.late" ] && IFS=$'\t' read -r n f r < "$1.late" || return 1
  if [ -n "$r" ]; then printf "conveyor: %s timed out: the run's time limit, %s s (testTimeout), stopped the run after the file ran %s s\n" "$f" "$r" "$n"
  else printf 'conveyor: %s timed out: it ran past its time limit, %s s, and the run was stopped there\n' "$f" "$n"; fi
}
# The bug-card check's result line for a run whose file timed out (<worktree>.late): it counts as failing without the fix.
latecount() { # <worktree>
  local n f r
  [ -s "$1.late" ] && IFS=$'\t' read -r n f r < "$1.late" || return 0
  if [ -n "$r" ]; then printf "%s timed out: the run's time limit, %s s, stopped it after it ran %s s. A test that hangs without the fix counts as failing without it.\n" "$f" "$r" "$n"
  else printf '%s timed out: it ran past its time limit, %s s, and was stopped. A test that hangs without the fix counts as failing without it.\n' "$f" "$n"; fi
}
# The times the runner's own report gives (the pack's test.report: format, and path, a file or folder from the
# worktree, else <worktree>.report (and each file's <worktree>.report.<n> of a card's run) when its env or args has
# <file> (reportask()), else the run's output, <worktree>.test
# (go test -v's, which env GOFLAGS asks for);
# conveyor/README.md, Test file times), as `TESTRUN sec` lines with clock seconds only
# (tools/testreport.py), in <worktree>.reported: of the report files written since <start>, so one an earlier run left
# is not read. None when the pack names no format.
reported() { # <worktree> <the run's start, epoch seconds>
  local f p e a ps
  rm -f "$1.reported"
  packget test.report.format f test.report.path p test.report.env e test.report.args a 2>/dev/null && [ -n "$f" ] || return 0
  if [[ $e$a == *'<file>'* ]]; then p=$1.report; elif [ -z "$p" ]; then p=$1.test; elif [[ $p != /* ]]; then p=$1/$p; fi
  ps=("$p"); [ "$p" != "$1.report" ] || for e in "$1".report.[0-9]*; do [ ! -e "$e" ] || ps+=("$e"); done
  python3 -I "$HERE/tools/testreport.py" "$f" "$1" "$2" "${ps[@]}" > "$1.reported" 2>/dev/null || rm -f "$1.reported"
}
# The changed lines no test reached, from the coverage report a card's run already writes (the pack's
# test.coverage: format and path, a file or folder from the worktree; conveyor/README.md, Changed lines no test
# reached), in <worktree>.uncovered for its test line (testrec()): the lines the staged patch adds that the report
# names and no report hit (tools/uncovered.py), or why they are unknown. Only the report files written since <start>
# are read, with the first run's that covkeep() kept when the run ran again. None when the pack names no format. A
# lead for the reviewer: it never fails a run, and starts none.
uncovered() { # <worktree> <the run's start, epoch seconds>
  local f p ps
  rm -f "$1.uncovered"
  packget test.coverage.format f test.coverage.path p 2>/dev/null && [ -n "$f" ] || return 0
  [[ $p == /* ]] || p=$1/$p
  ps=("$p"); [ ! -d "$1.covfirst" ] || ps+=("$1.covfirst")
  git -C "$1" -c core.quotePath=false diff --cached -U0 --no-renames --no-color HEAD -- 2>/dev/null \
    | python3 -I "$HERE/tools/uncovered.py" "$f" "$1" "$2" "${ps[@]}" > "$1.uncovered" 2>/dev/null \
    || printf '{"unknown":"the coverage report could not be read"}\n' > "$1.uncovered"
}
# A card's run that runs again (tests()): its first run's coverage report, which the run again may write over at the
# same path (the pack's test.coverage.path), copied with its file times into <worktree>.covfirst for uncovered(), so
# the lines the first run's tests reached stay reached. None when the pack names no format or no report is there.
covkeep() { # <worktree>
  local f p
  rm -rf "$1.covfirst"
  packget test.coverage.format f test.coverage.path p 2>/dev/null && [ -n "$f" ] || return 0
  [[ $p == /* ]] || p=$1/$p
  [ ! -e "$p" ] || { mkdir "$1.covfirst" && cp -Rp "$p" "$1.covfirst/"; } 2>/dev/null || rm -rf "$1.covfirst"
}
# What the next run of the card need not run again (tests()), in <worktree>.rerun: a line `change\t<id>` (the hash of
# the staged diff), `base\t<HEAD>` and `tree\t<the index's tree>` (what rerunsince() compares), then `pass\t<file>` for
# each file that passed in this run or one before it, `ok\t<file>\t<case>` for each case that passed in a file that
# did not (in this run or one before it), and `fail\t<file>\t<case>` for each case that failed in this run. A file
# with no line (it failed naming no case, never finished or never began) runs whole. Of a file that ran in this run,
# case by case, what the list said before goes only where this run says otherwise: a case that failed now is no
# longer kept as passed, and every other case it kept still is (a run after a fix runs a few cases of the engine's
# runner, and the runner's cases it did not run stay kept). A file `pass` before that now failed naming its cases keeps
# its `pass` line beside their `fail` lines: the command runs those cases alone. A file that now failed naming no case
# or never finished, when the run's log names the cases it selected of it (`TESTRUN case\t<file>\t<case>`, a file
# run in part), loses only what it kept of those cases: its `ok` lines of them go, and a `pass` line stays beside a
# `fail` line for each of them that did not print `ok` now, so its other cases, which did not run (a fix's run of the
# cases of the files the fix changed, then the run's timeout), stay kept. Else (a file run whole, or a log that names
# no case) it keeps no `pass` line, nor, in a run that was given `changed` lines (rerunsince()), its `ok` lines.
# With no HEAD or tree (git write-tree failed, as under load) it keeps no list: the next run could not compare the
# trees, and the refused full run (tests()) would keep the passes, so a fix's changed files would not run their tests.
rerunlist() { # <worktree> <the staged change's id> <testfails() of the run> <HEAD> <tree>
  local old ran='' sel='' logs=() ch=''
  [ -n "${4:-}" ] && [ -n "${5:-}" ] || { rm -f "$1.rerun"; return 0; }
  ! grep -q $'^changed\t' "$1.rerun" 2>/dev/null || ch=1
  mapfile -t logs < <(testlogs "$1")
  if [ ${#logs[@]} != 0 ]; then
    ran=$(cat "${logs[@]}" 2>/dev/null | sed -n 's/^== //p'); sel=$(cat "${logs[@]}" 2>/dev/null | sed -n 's/^TESTRUN case\t//p')
  fi
  old=$(jq -rRn --rawfile ran <(printf '%s' "$ran") --rawfile sel <(printf '%s' "$sel") --arg ch "$ch" --slurpfile r <(printf '%s' "$3") '
    $r[0] as $r | ($ran | split("\n") | map(select(. != ""))) as $ran
    | ($sel | split("\n") | map(select(. != "") | split("\t"))) as $sel
    | inputs | split("\t") | select(.[0] == "pass" or .[0] == "ok") | . as [$k, $f, $c]
    | [$r.files[]? | select(.file == $f)] as $fl | [$fl[].cases[].name] as $n
    | [$sel[] | select(.[0] == $f) | .[1]] as $s
    | if IN($ran[]; $f) | not then join("\t")
      elif IN($r.passed[]?; $f) then empty
      elif $fl != [] and $n != [] then select($k == "pass" or (IN($n[]; $c) | not)) | join("\t")
      elif $s == [] then select($k == "ok" and $ch == "") | join("\t")
      elif $k == "ok" then select(IN($s[]; $c) | not) | join("\t")
      else join("\t"), ($s - [$r.okcases[]? | select(.file == $f) | .cases[]] | unique | .[] | "fail\t\($f)\t\(.)") end' "$1.rerun" 2>/dev/null)
  { printf 'change\t%s\nbase\t%s\ntree\t%s\n' "$2" "${4:-}" "${5:-}"
    { sed -n 's/^pass\t//p' <<<"$old"; jq -r '.passed[]?' <<<"$3"; } | sort -u | sed 's/^/pass\t/'
    { sed -n 's/^ok\t//p' <<<"$old"; jq -r '.okcases[]? | .file as $f | .cases[] | "\($f)\t\(.)"' <<<"$3"; } | sort -u | sed 's/^/ok\t/'
    { jq -r '.files[] | .file as $f | .cases[] | "\($f)\t\(.name)"' <<<"$3"; sed -n 's/^fail\t//p' <<<"$old"; } | awk '!s[$0]++' | sed 's/^/fail\t/'
  } > "$1.rerun.new" && mv -f "$1.rerun.new" "$1.rerun"
}
# What a card's run that passed passed (tests()), for a batch that takes the card (batchkeep()): <worktree>.passed,
# {units, cases}. units: each test file the run passed, as `<file>`, or, of a file whose log lines `ok <case>` name
# its cases, as `<file><TAB><case>` for each case; with what the run's list (<worktree>.rerun) kept as passed, and a
# file passed whole standing for its cases. A run whose command wrote no log is one file, the command (test.command).
# cases: how many cases the run ran and kept (testrec()), null when its runner does not say.
passlist() { # <worktree>
  local f cmd
  if [ -n "$(testlogs "$1")" ]; then f=$(testfails "$1.test" 0) || return 1
  else packget test.command cmd && f=$(jq -cn --arg c "$cmd" '{passed: [$c], passcases: [], okcases: []}') || return 1; fi
  { awk -F'\t' '$1 == "pass" {print $2} $1 == "ok" {print $2 "\t" $3}' "$1.rerun" 2>/dev/null
    jq -r '((.passcases + .okcases)[] | .file as $f | .cases[] | "\($f)\t\(.)"), (.passed - [.passcases[].file])[]' <<<"$f"
  } | jq -cRn --slurpfile x <(testrec "$1" 0 0) '$x[0] as $x | [inputs | select(. != "")] | unique as $u | [$u[] | select(contains("\t") | not)] as $w
    | {units: [$u[] | select((contains("\t") | not) or (split("\t")[0] | IN($w[]) | not))],
       cases: (if $x.selected.cases == null and $x.selected.kept == null then null else ($x.selected.cases // 0) + ($x.selected.kept // 0) end)}' > "$1.passed"
}
# Whether the card of a worktree has a test line in the records: a run of its tests ended before (tests()).
testedbefore() { # <worktree>
  [ "$(stdb ask tested "${1##*/}" 2>/dev/null)" = true ]
}
# A card's run (tests()): each file of a case the last run's list (<worktree>.rerun) names as failed (a `fail` line with
# a case), that is still there, that the card's change selects (testsel() narrow) and that is not on the card's list
# (TEST_FILES), is added to it and to the count of files the run is given (TEST_GIVEN, and <worktree>.testlist's
# files). A fix that edited only a test file has that file as its list (listcmd(): by own), and without this the case
# that had failed did not run again. A `fail` line with no case (unshare()) or of a file the card's change does not
# select (a batch's run, of another card's change) adds nothing.
failsleft() { # <worktree>
  local f n=$TEST_GIVEN fs s
  fs=$(awk -F'\t' '$1 == "fail" && $2 != "" && $3 != "" && !s[$2]++ { print $2 }' "$1.rerun" 2>/dev/null | grep -vxF -f <(printf '%s\n' "$TEST_FILES")) \
    && s=$(testsel "$1" narrow 2>/dev/null) || return 0
  while IFS= read -r f; do
    [ -f "$1/$f" ] && grep -qxF -- "$f" <<<"${s#*$'\n'}" || continue
    TEST_FILES+=$'\n'$f; TEST_GIVEN=$((TEST_GIVEN + 1))
  done <<<"$fs"
  [ "$n" = "$TEST_GIVEN" ] || { jq -c --argjson n "$TEST_GIVEN" '.files = $n' "$1.testlist" > "$1.testlist.new" && mv -f "$1.testlist.new" "$1.testlist"; } \
    || rm -f "$1.testlist.new"
}
# A card's run (tests()) after a session changed the change or main moved (the list has a `changed` or `main` line): of its
# files (TEST_FILES), the ones the list keeps something of (a `pass` line, or an `ok` or `off` line: a case that passed in a run
# killed part-way, or one kept off as flaky; no `fail` line) and that the changed-tests command (test.command) selects no case of
# are not started: each start of test.fileCommand costs its set-up and runs no case, and what the list kept stands.
# The command lists, in CONVEYOR_TEST_LIST, the test files whose cases it selects for the list (CONVEYOR_TEST_FILELIST,
# CONVEYOR_TEST_RERUN) and the cases the card named of each (CONVEYOR_TEST_CASES, as a start of a file gets them), as
# suitereuse() asks it; and it logs the cases it keeps of the files it leaves out in CONVEYOR_TEST_LOG, which testrec() sums.
# Only a pack that sets test.changed (the command reads `changed` and `main` lines) is asked; with none, or when the command
# fails or writes no list, every file is started; a list that names none of them starts none of those the list kept something of.
# A file the list holds no line of is always started, so a file the command cannot select (an engine case file with no case) fails in its own run.
runfiles() { # <worktree>
  local cmd tc
  grep -qE $'^(changed|main)\t' "$1.rerun" 2>/dev/null && [ -n "${TEST_FILES:-}" ] && packget test.changed tc && [ -n "$tc" ] \
    && packget test.command cmd && [ -n "$cmd" ] || return 0
  rm -f "$1.runsel"; printf '%s\n' "$TEST_FILES" > "$1.runfiles" \
    && (cd "$1" && CONVEYOR_TEST_LIST=$1.runsel CONVEYOR_TEST_RERUN=$1.rerun CONVEYOR_TEST_FILELIST=$1.runfiles CONVEYOR_TEST_CASES=${TEST_CASES:-} CONVEYOR_TEST_LOG=$1.testlog \
      timeout 300 bash -c "$cmd" > "$1.runsel.out" 2>&1 < /dev/null 8>&-) \
    && [ -f "$1.runsel" ] && TEST_FILES=$(awk -F'\t' 'FILENAME == ARGV[1] { sel[$0] = 1; next }
      FILENAME == ARGV[2] { if ($1 == "pass" || $1 == "ok" || $1 == "off") p[$2] = 1; else if ($1 == "fail") f[$2] = 1; next }
      !(($0 in p) && !($0 in f) && !($0 in sel))' "$1.runsel" "$1.rerun" "$1.runfiles")
  rm -f "$1.runsel" "$1.runsel.out" "$1.runfiles"; return 0
}
# The files that differ between two trees or commits, one a line (read NUL-separated: a name with spaces is whole).
treediff() { # <worktree> <from> <to>
  git -C "$1" diff --name-only --no-renames -z "$2" "$3" -- > "$1.rerun.new" 2>/dev/null && tr '\0' '\n' < "$1.rerun.new"
}

# The clock of a test run (tests()): TEST_TIMEOUT seconds of running times the run's load factor (testonce() scales it
# with LOADSCALE, as each file's own limit is scaled: filecmd(), lib/testrun.sh), the seconds a runner of its command waited for
# a whole-suite turn not counted (slot_whole writes them to <turn wait file>), as the wait for its slot is not (the
# owner, 2026-11-13: no time limit changes for the turns). timeout itself is given no limit; when the clock runs out
# it is sent ALRM, its own timer's signal, so it ends the run as on its own timeout: TERM to the command's group, KILL
# 30 s later, exit 124. It holds no descriptor of the loop's (a lock, the slot) while it runs.
# With TEST_LATE (the bug-card check's run, bugrun()), when the run's own limit ends the run, a file the runner's logs
# (testlogs(); its output when it wrote none) name as begun (`== <file>`), not ended (`-- ok|FAIL <file>`, or the
# output's line that its own `# timeout:` limit stopped it, which filecmd() writes in place of `-- FAIL`) and not
# stopped by its own limit (`-- timeout <file>`, filecmd(), lib/testrun.sh) is named
# in <worktree>.late as `<seconds><TAB><file><TAB><limit>`: the seconds it ran (from the last look that did not see it
# begun, so never fewer than it ran, and at most a look's second more), and the run's limit (TEST_TIMEOUT, scaled).
# Bug (R332): the line held the limit as the file's seconds, so a file that began after others had used most of the
# run's time was said to have run past its time limit; timed from the first look that saw it begun, a file that began
# just after a look and ran to the limit at the next was said to have run 0 s. A file's own limit is its run's
# (filecmd()). Bug: a file its own limit stopped gets no `-- ok|FAIL` line, so it stayed open, and the proof said the
# run's limit stopped it though a later file hung, or ended its run (its runner logs `-- ok` before its own cleanup:
# .conveyor/test-changed.sh). Its `-- timeout` line ends it, in whatever log order. Of the files left open, the one
# begun last is named, by the first `== ` line of each in the logs: the runner's log `files` has the files in the
# order they began and is read before `test-changed.log`, which logs a file's `== ` line only once it ended or was told
# to end; named by awk's array order, or by its last `== ` line, a file begun before was named in place of the one
# begun after it.
testclock() { # <timeout's pid> <turn wait file> <the run's limit: TEST_TIMEOUT, scaled>
  local s=$SECONDS w wt=${2%.turnwait} f open l=() lim=${3:-${TEST_TIMEOUT:-3600}} p=$SECONDS now
  local -A at=() # at: the last look before each file was seen begun (p: the look before this one), for its own seconds
  closefds
  exec </dev/null >/dev/null 2>&1
  while sleep 1; do
    if [ -n "${TEST_LATE:-}" ]; then
      now=$SECONDS
      mapfile -t l < <(testlogs "$wt"); [ ${#l[@]} != 0 ] || l=("$wt.test")
      open=
      while IFS= read -r f; do open=$f; [ -n "${at[$f]:-}" ] || at[$f]=$p
      done < <({ cat "${l[@]}"; [ "${l[0]}" = "$wt.test" ] || grep -a '^conveyor: .* timed out: it ran past its time limit' "$wt.test"; } 2>/dev/null \
        | awk '/^== / { f = substr($0, 4); o[f] = 1; if (!(f in r)) { r[f] = ++n; b[n] = f } } /^-- ok / { delete o[substr($0, 7)] }
        /^-- FAIL / { delete o[substr($0, 9)] } /^-- timeout / { x[substr($0, 12)] = 1 }
        /^conveyor: .* timed out: it ran past its time limit, [0-9]+ s, and it was stopped there(; the limit is .*)?$/ {
          f = substr($0, 11); sub(/ timed out: it ran past its time limit, [0-9]+ s, and it was stopped there(; the limit is .*)?$/, "", f); delete o[f] }
        END { for (i = 1; i <= n; i++) if ((b[i] in o) && !(b[i] in x)) print b[i] }')
      p=$now
    fi
    w=$(cat "$2" 2>/dev/null); [[ $w =~ ^[0-9]{1,9}$ ]] || w=0
    [ $((SECONDS - s)) -ge $((lim + w)) ] || continue
    [ -z "${open:-}" ] || printf '%s\t%s\t%s\n' "$((SECONDS - ${at[$open]:-$s}))" "$open" "$lim" > "$wt.late"
    kill -ALRM "$1"; return
  done
}
# The list of the card's last run (testlist.sh rerunlist()) for its run now: kept as it is for the same staged change on the same
# HEAD; for a change made on the same HEAD (a fix session's), with a line `changed\t<file>` for each file whose content
# differs between the tree last tested and the tree now (the two trees compared, not the two patches), so the command
# runs their tests beside what had not passed. On another HEAD (the change moved onto a newer main, or a retried card's
# kept list on a main that moved since: the owner, 2026-11-14), `changed` lines for the files of the card's change, as
# it was or is now, whose content differs between the two trees, and a line `main\t<file>` for each file main changed
# between the HEAD last tested and HEAD now, whose tests the command runs when its selection for the card's change
# holds them too, and a line `from\t<the HEAD last tested>`, so the command can read what main changed in each (a
# change of text alone runs only the tests that hold the text: test-changed.sh, issue 512). Fails (1), and the whole selection would run, when there is no list, the change has no id, or the
# trees or HEADs cannot be compared, RERUN_WHY saying which (tests() refuses such a full run unless it is allowed).
# Fails (2), the whole selection to run, when HEAD moved and a file of the card's change that main did not change
# differs: the session that brought the change onto main (the rebuild, the port) edited it outside what main changed,
# a merge in doubt.
# shellcheck disable=SC2034 # RERUN_WHY is read by tests() in lib/testrun.sh
rerunsince() { # <worktree> <the staged change's id> <HEAD> <tree>
  local ot ob ch m='' c rd
  RERUN_WHY='no list of what the last run passed'
  [ -n "$2" ] && [ -s "$1.rerun" ] || return 1
  ob=$(sed -n 's/^base\t//p' "$1.rerun"); ot=$(sed -n 's/^tree\t//p' "$1.rerun")
  [ "$(sed -n '1s/^change\t//p' "$1.rerun")" != "$2" ] || [ "$ob" != "$3" ] || return 0
  RERUN_WHY="the last run's list names no tree or commit to compare with"
  [ -n "$3" ] && [ -n "$4" ] && [ -n "$ot" ] && [ -n "$ob" ] || return 1
  RERUN_WHY="the tree last tested ($ot) cannot be compared with the tree now"
  ch=$(treediff "$1" "$ot" "$4") || return 1
  if [ "$ob" != "$3" ]; then
    RERUN_WHY="the commit last tested on ($ob) cannot be compared with HEAD"
    m=$(treediff "$1" "$ob" "$3") && c=$(treediff "$1" "$ob" "$ot" && treediff "$1" "$3" "$4") || return 1
    ch=$(grep -xF -f <(grep . <<<"$c") <<<"$ch")
    ! grep -vxF -f <(grep . <<<"$m") <<<"$ch" | grep -q . || return 2
  fi
  # A test file whose last pass on record read a file that differs between the two trees (cachereaders(), #1619) keeps
  # no `pass`, `ok` or `fail` line, so it runs whole though the command selects none of it (runfiles()): bug, a fix
  # that changed a file a passed test read kept that pass, and runfiles() left the test off.
  RERUN_WHY="the files that differ between the tree last tested ($ot) and the tree now cannot be read"
  rd=$(git -C "$1" -c core.quotePath=false diff --name-status --no-renames "$ot" "$4" -- 2>/dev/null) && rd=$(cachereaders "$rd") || return 1
  RERUN_WHY="the list for this run could not be written"
  { printf 'change\t%s\nbase\t%s\ntree\t%s\n' "$2" "$3" "$4"; [ "$ob" = "$3" ] || printf 'from\t%s\n' "$ob"
    grep -E $'^(pass|ok|fail|shared)\t' "$1.rerun" | awk -F'\t' -v R="$rd" 'BEGIN { n = split(R, x, "\n"); for (i = 1; i <= n; i++) d[x[i]] = 1 }
      $1 == "shared" || !($2 in d)'; awk 'length { print "changed\t" $0 }' <<<"$ch"; awk 'length { print "main\t" $0 }' <<<"$m"; } > "$1.rerun.new" \
    && mv -f "$1.rerun.new" "$1.rerun"
}
# The test files a card's run again adds to its list on a main that moved (listcmd(): MAINFROM is the commit its list was
# tested on): the ones .conveyor/test-links.json gives under "main:<file>" for each <file> main changed since, those
# still there, each run whole. A file main changed whose tests no change of the card selects (the pack's map, whose own
# tests run when main changes it) would otherwise never run on a list of one-file runs.
mainlinks() { # <worktree> <the commit last tested on>
  git -C "$1" -c core.quotePath=false diff --name-only --no-renames "$2" HEAD -- 2>/dev/null \
    | jq -Rr --slurpfile m <(cat "$1/.conveyor/test-links.json" 2>/dev/null || echo '{}') '$m[0]["main:" + .] | arrays[] | strings' 2>/dev/null \
    | sort -u | while IFS= read -r f; do [ ! -f "$1/$f" ] || printf '%s\n' "$f"; done
}
# A run's logs <log>... that name a file the runner did not start for a problem of the host, as no room in the temp
# space (a line `TESTRUN host<TAB><file><TAB><why>`), and no failed test: each file logged `-- FAIL` or `-- timeout` is
# such a file (a test.fileCommand run, fileeach(), logs `-- FAIL` for the runner's failed exit on it). Prints the first
# why; fails when no file is such a file, or a test failed. Bug #1662: such a file was a failed test, so it ran on main,
# failed there for the same want of room, and main was marked red with nothing to fix (voidrun(), lib/testrun.sh).
hostonly() { # <log>...
  local h
  h=$(grep -h $'^TESTRUN host\t' "$@" 2>/dev/null | cut -f2-) && [ -n "$h" ] || return 1
  ! grep -hE '^-- (FAIL|timeout) ' "$@" 2>/dev/null | cut -d' ' -f3- | grep -qvxF -f <(cut -f1 <<<"$h") || return 1
  h=$(head -n 1 <<<"$h"); printf '%s\n' "${h#*$'\t'}"
}
