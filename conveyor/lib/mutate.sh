# SPDX-License-Identifier: Apache-2.0
# Mutation checks of test files (README.md, Mutation checks): does a test file fail when the code it tests is changed?
# `conveyor.sh mutate <test file>` checks one file now; the loop's idle job (mutnext(), started by `serve`) checks the
# files of its queue one after another while the machine is idle. A card's own steps never run one.
# One check: the source files the test file covers (mutsources()), up to MUTMAX mutants of them, one line each
# (jq/mutants.jq), picked at random with a seed it records (mutsample()), each applied in a worktree of main's commit
# ($CARDS/mutate/<id>, removed when the check stops or ends) and the test file run alone there with the pack's
# test.command on a test slot (mutone()): killed (it failed), survived (it passed) or no result (it timed out, or did
# not run). The file is first run with no mutant: a file that fails so says nothing of its mutants, and the check
# ends failed. A source of a kind the rules do not read (not shell, JavaScript or TypeScript) is not mutated.
# A mutant starts only when no card of this project is in its build or test step, no test run of any project on the
# machine asks for a test slot or holds one, and the machine's 1-minute load is below its Load limit (the host file's
# maxLoad), mutheld(); a mutant that runs is stopped at once when a card of any project asks for a test slot. The check then stops, and resumes from its next mutant later, on the
# commit it began on. One check runs at a time ($MUTS/lock).
# Each check's record, in $MUTS/<id>.json: {id, action: "mutate", file, project, at (its start), sha (main's commit it
# checks), seed, state (running, stopped, done or failed), pid (while it runs), reason (stopped or failed: why), base
# (the run with no mutant: pass, fail or null before it), next (the index of the next mutant to run), mutants (each
# {source, line, kind, before, after}), tried, killed, survived (each mutant that survived, as mutants has it),
# noresult, notMutated (the sources of a kind the rules do not read), blobs (the test file's and its sources' blobs at
# sha: the queue checks the file again when one of them changes on main), end}.
MUTMAX=20
mutkind() { # <path>: sh or js; 1 for a kind the rules do not read
  case $1 in *.sh | *.bash) echo sh ;; *.js | *.mjs | *.cjs | *.jsx | *.ts | *.tsx | *.mts | *.cts) echo js ;; *) return 1 ;; esac
}
# The source files <test file> covers, in <worktree>, one a line: each tracked file it imports (JavaScript or
# TypeScript: from, import or require of a path that starts with ./ or ../, with or without its extension or
# /index) or sources (shell: `. <path>` or `source <path>`; a path that starts with a variable or a $( ) is read from
# after it, beside the test file, from the top, or as the one tracked file whose path ends so). None of those: the
# tracked files whose name is the test file's up to .test. or .spec. Never a test file.
mutsources() { # <worktree> <test file>
  local k
  k=$(mutkind "$2") || k=''
  jq -rn --rawfile src "$1/$2" --arg t "$2" --arg k "$k" --rawfile ls <(git -C "$1" -c core.quotePath=false ls-files) '
    ($ls | split("\n") | map(select(. != ""))) as $all | ($all | map({key: ., value: true}) | from_entries) as $has
    | def norm: split("/") | reduce .[] as $p ([]; if $p == "" or $p == "." then . elif $p == ".." then .[:-1] else . + [$p] end) | join("/");
      def rel($p): ($t | split("/") | .[:-1] | join("/")) as $d | (if $d == "" then $p else $d + "/" + $p end) | norm;
      def istest: split("/")[-1] | test("\\.(test|spec)\\.");
    [ if $k == "js" then
        $src | scan("(?:\\bfrom\\s*|\\brequire\\s*\\(\\s*|\\bimport\\s*\\(\\s*|\\bimport\\s+)[\"\\x27\\x60](\\.{1,2}/[^\"\\x27\\x60]+)[\"\\x27\\x60]")[0] | rel(.) as $b
        | first(($b, $b + (".js", ".mjs", ".cjs", ".jsx", ".ts", ".tsx", ".mts", ".cts"), $b + "/index" + (".js", ".mjs", ".ts", ".tsx", ".jsx")) | select($has[.]))
      elif $k == "sh" then
        $src | split("\n")[] | capture("^\\s*(\\.|source)\\s+(?<p>.+)$").p | sub("\\s*(\\|\\||&&|;|\\s#).*$"; "") | gsub("[\"\\x27]"; "")
        | if test("\\$") then sub("^.*(\\)|\\}|\\$[A-Za-z_][A-Za-z0-9_]*)/"; "") | select(test("\\$") | not) | . as $r
            | first((rel($r), ($r | norm)) | select($has[.])) // ([$all[] | select(endswith("/" + $r))] | if length == 1 then .[0] else empty end)
          else first((rel(.), norm) | select($has[.])) end
      else empty end ] | map(select(istest | not)) | unique
    | if . != [] then . else ($t | split("/")[-1] | sub("\\.(test|spec)\\..*$"; "")) as $s | [$all[] | select((istest | not) and (split("/")[-1] | startswith($s + ".")))] end
    | .[]'
}
# The check's mutants, as its record keeps them: those of each source <worktree> has (jq/mutants.jq), up to MUTMAX
# picked at random from <seed> (a Fisher-Yates shuffle cut short, on the Park-Miller generator, so a seed picks the
# same mutants on any machine). Sets MUT_LIST (a JSON list) and MUT_NOT (the sources not mutated, a JSON list).
mutsample() { # <worktree> <seed> <source>...
  local wt=$1 s=$2 f k all='' not=()
  shift 2
  for f in "$@"; do
    if k=$(mutkind "$f"); then all+=$(jq -Rnc --arg kind "$k" -f "$HERE/jq/mutants.jq" < "$wt/$f" | jq -c --arg s "$f" '{source: $s} + .')$'\n' || return 1
    else not+=("$f"); fi
  done
  MUT_NOT=$(jq -cn '$ARGS.positional' --args "${not[@]}")
  MUT_LIST=$(printf '%s' "$all" | jq -cs --argjson s "$s" --argjson n "$MUTMAX" '
    reduce range(0; [$n, length] | min) as $i ({a: ., x: $s};
      .x = (.x * 16807) % 2147483647 | ($i + (.x % ((.a | length) - $i))) as $j | .a[$i] as $t | .a[$i] = .a[$j] | .a[$j] = $t)
    | .a[:$n]')
}
# Why no mutant may start now, printed, and 0; 1 when one may. [steps]: the steps of a card that hold it back (build
# and test); with test alone, the load is not looked at (a mutant that runs is stopped only by a card that asks for a
# slot). A card's step is its live record's ($CARDS/<card>.live). A test run of any project on the machine, which
# shares the test slots, holds it back too while it asks for a slot or holds one (slot_ask(), lib/slots.sh).
mutheld() { # [steps, as an extended pattern: build|test]
  local f s m l
  for f in "$CARDS"/*.live; do
    [ -e "$f" ] && s=$(jq -r '.step | strings' "$f" 2>/dev/null) || continue
    [[ $s =~ ^(${1:-build|test})$ ]] || continue
    f=${f##*/}; echo "card ${f%.live} is in its $s step"; return 0
  done
  [ -n "${SLOT_DIR:-}" ] || slot_pool > /dev/null 2>&1 || :
  if [ -n "${SLOT_DIR:-}" ] && s=$(slot_asked); then echo "$s test run(s) on this machine ask for a test slot or hold one"; return 0; fi
  [ -z "${1:-}" ] && m=$(jq -er '.maxLoad | numbers' "$HOST" 2>/dev/null) || return 1
  l=$(p_load)
  jq -en --arg l "$l" --argjson m "$m" '($l | tonumber? // null) as $l | $l != null and $l < $m' > /dev/null && return 1
  echo "the load ${l:-(not read)} is not below the Load limit $m"
}
# The test file <file> run alone in <worktree> as it is now, on a test slot, as `testaction run` runs one (tests());
# MUT_RES is killed, survived, noresult or stopped: a card asked for a slot while it ran (MUT_WHY says which), and it
# was ended at once, with every process it started, so the slot is free for the card. Its list names every other test
# file of the worktree as passed, so no test the mutant's change selects runs beside it, and only <file> can kill it.
# The run makes no ask (MUT_RUN, tests()), so it does not hold back itself or another project's check.
mutone() { # <worktree> <file>
  local wt=$1 tp x s
  { printf 'fail\t%s\n' "$2" && git -C "$wt" -c core.quotePath=false ls-files \
      | while IFS= read -r x; do [[ $x != "$2" && ${x##*/} =~ \.(test|spec)\. ]] || continue; printf 'pass\t%s\n' "$x"; done; } > "$wt.rerun" \
    && rm -f "$wt.res" || { MUT_RES=noresult; return; }
  # shellcheck disable=SC2034 # MUT_RUN is read by tests() in lib/testrun.sh
  ( MUT_RUN=1; tests "$wt" test.command alone; x=$?; printf '%s\t%s\n' "$x" "$TEST_RUN" > "$wt.res" ) & tp=$!
  while kill -0 "$tp" 2>/dev/null; do
    if MUT_WHY=$(mutheld test); then taend "$tp"; wait "$tp" 2>/dev/null; MUT_RES=stopped; return; fi
    sleep 0.2
  done
  wait "$tp"
  if IFS=$'\t' read -r x s < "$wt.res" 2>/dev/null && [ -n "$s" ] && [ "$x" != 124 ]; then
    if [ "$x" = 0 ]; then MUT_RES=survived; else MUT_RES=killed; fi
  else MUT_RES=noresult; fi
}
mutrecs() { # every check's record, a JSON list
  local fs=()
  [ ! -d "$MUTS" ] || fs=("$MUTS"/*.json)
  [ -e "${fs[0]:-}" ] || { echo '[]'; return; }
  jq -cs 'map(objects)' "${fs[@]}" 2>/dev/null || echo '[]'
}
# 0 when <file> is a test file of main's <commit>: a tracked file whose own name has .test. or .spec. in it.
mutfile() { # <file> <main's commit>
  local f=$1
  [[ -n $2 && -n $f && $f != /* && /$f/ != */../* && /$f/ != */./* && $f != *$'\n'* && ${f##*/} =~ \.(test|spec)\. ]] \
    && [ "$(git -C "$MAIN" cat-file -t "$2:$f" 2>/dev/null)" = blob ]
}
# `conveyor.sh mutate <test file>`: one check of a test file of main, now, in this process; a check of it that
# stopped resumes. Refused (exit 2) for a path that is not a test file of main, or while another check runs.
# `conveyor.sh mutate ask <test file>...` (mutask()) puts files at the front of the idle queue.
mutate() { # <test file> | ask <test file>...
  [ "${1:-}" != ask ] || { shift; mutask "$@"; return; }
  local f=${1:-} sha rc
  sha=$(git -C "$MAIN" rev-parse -q --verify "refs/heads/$BRANCH^{commit}" 2>/dev/null)
  mutfile "$f" "$sha" || { echo "conveyor: $f is not a test file of $BRANCH; nothing checked" >&2; return 2; }
  mkdir -p "$MUTS" && { exec {MUTLOCK}>>"$MUTS/lock"; } 2>/dev/null || { echo "conveyor: the mutation checks' folder could not be made; nothing checked" >&2; return 1; }
  flock -n "$MUTLOCK" || { exec {MUTLOCK}>&-; echo "conveyor: a mutation check already runs; nothing checked" >&2; return 2; }
  mutrun "$f" "$sha"; rc=$?; exec {MUTLOCK}>&-
  return $rc
}
# The check of <file>, under the lock: the newest one of it that has not ended (stopped, or running when the engine
# running it was ended) resumes; else a new one, on main's <commit>. Prints its id and the state it is left in.
mutrun() { # <file> <main's commit>
  local f=$1 sha=$2 r id wt out src=() seed i m n why
  r=$(mutrecs | jq -c --arg f "$f" 'map(select(.file == $f and (.state == "stopped" or .state == "running"))) | max_by(.at) // empty')
  if [ -n "$r" ]; then
    id=$(jq -r .id <<<"$r"); sha=$(jq -r .sha <<<"$r")
  else
    id=$(od -An -N6 -tx1 /dev/urandom | tr -d ' \n')
    r=$(jq -cn --arg id "$id" --arg f "$f" --arg p "$REPO" --arg t "$(clock)" --arg h "$sha" '{id: $id, action: "mutate", file: $f, project: $p, at: $t, sha: $h,
      seed: null, state: "running", base: null, next: 0, mutants: [], tried: 0, killed: 0, survived: [], noresult: 0, notMutated: [], blobs: {}, end: null}')
  fi
  wt=$CARDS/mutate/$id
  mutunask "$f"
  r=$(jq -c --argjson p "$BASHPID" '.state = "running" | .pid = $p | del(.reason)' <<<"$r")
  taput "$MUTS/$id.json" "$r" || { echo "conveyor: the record of the mutation check could not be written; nothing checked" >&2; return 1; }
  if out=$({ tadrop "$wt"; rm -rf "$wt".*; mkdir -p "${wt%/*}" && git -C "$MAIN" worktree add -q --detach "$wt" "$sha" && deps "$wt"; } 2>&1 < /dev/null); then
    if [ "$(jq -r .seed <<<"$r")" = null ]; then
      mapfile -t src < <(mutsources "$wt" "$f")
      seed=$(( (RANDOM * 32768 + RANDOM) % 2147483646 + 1 ))
      if mutsample "$wt" "$seed" "${src[@]}"; then
        r=$(jq -c --argjson s "$seed" --argjson m "$MUT_LIST" --argjson n "$MUT_NOT" --slurpfile b <(git -C "$wt" ls-tree HEAD -- "$f" "${src[@]}" | jq -Rn '[inputs | capture("^\\S+ blob (?<b>\\S+)\t(?<p>.*)$") | {key: .p, value: .b}] | from_entries') \
          '. + {seed: $s, mutants: $m, notMutated: $n, blobs: $b[0]}' <<<"$r")
      else r=$(jq -c '.state = "failed" | .reason = "its mutants could not be made"' <<<"$r"); fi
    fi
  else r=$(jq -c --arg w "the copy of main it runs in could not be made: ${out:0:300}" '.state = "failed" | .reason = $w' <<<"$r"); fi
  while [ "$(jq -r .state <<<"$r")" = running ]; do
    i=$(jq -r .next <<<"$r"); n=$(jq -r '.mutants | length' <<<"$r")
    # Done once each mutant has a result; a check with no mutant needs no run.
    [ "$n" = 0 ] || { [ "$(jq -r .base <<<"$r")" != null ] && [ "$i" -ge "$n" ]; } && { r=$(jq -c '.state = "done"' <<<"$r"); break; }
    if why=$(mutheld); then r=$(jq -c --arg w "$why" '.state = "stopped" | .reason = $w' <<<"$r"); break; fi
    if [ "$(jq -r .base <<<"$r")" = null ]; then
      mutone "$wt" "$f"
      case $MUT_RES in
        stopped) r=$(jq -c --arg w "$MUT_WHY" '.state = "stopped" | .reason = $w' <<<"$r") ;;
        survived) r=$(jq -c '.base = "pass"' <<<"$r") ;;
        *) r=$(jq -c '.base = "fail" | .state = "failed" | .reason = "the test file does not pass with no mutant: its mutants would say nothing"' <<<"$r") ;;
      esac
    else
      m=$(jq -c ".mutants[$i]" <<<"$r")
      # The source with the mutant's line in place of its own, then as it was again.
      git -C "$wt" show "HEAD:$(jq -r .source <<<"$m")" | MUT_AFTER=$(jq -r .after <<<"$m") awk -v n="$(jq -r .line <<<"$m")" 'NR == n { print ENVIRON["MUT_AFTER"]; next } { print }' > "$wt/$(jq -r .source <<<"$m")" \
        && mutone "$wt" "$f" || MUT_RES=noresult
      git -C "$wt" show "HEAD:$(jq -r .source <<<"$m")" > "$wt/$(jq -r .source <<<"$m")"
      case $MUT_RES in
        stopped) r=$(jq -c --arg w "$MUT_WHY" '.state = "stopped" | .reason = $w' <<<"$r") ;;
        killed) r=$(jq -c '.next += 1 | .tried += 1 | .killed += 1' <<<"$r") ;;
        survived) r=$(jq -c --argjson m "$m" '.next += 1 | .tried += 1 | .survived += [$m]' <<<"$r") ;;
        *) r=$(jq -c '.next += 1 | .tried += 1 | .noresult += 1' <<<"$r") ;;
      esac
    fi
    taput "$MUTS/$id.json" "$r"
  done
  tadrop "$wt"; rm -rf "$wt".*
  r=$(jq -c --arg t "$(clock)" 'del(.pid) | if .state == "stopped" then . else .end = $t end' <<<"$r")
  taput "$MUTS/$id.json" "$r"
  echo "conveyor: mutation check $id of $f: $(jq -r '.state + (if .reason then ": " + .reason else "" end) + " (\(.tried) of \(.mutants | length) tried, \(.killed) killed, \(.survived | length) survived, \(.noresult) with no result)"' <<<"$r")"
}
# The idle queue, the test files of main's <commit> to check, first to last: those with no check that ended (done or
# failed), or whose test file or a source changed on main since their newest such check (its blobs). The files the
# Tests page flags go first: "Never caught anything" (NEVER_RUNS runs on record or more and no catch, as the Board
# counts them) or hollow (the cheap check's hollow cases, or a judge's HOLLOW lines); then the files checked longest
# ago, a file never checked before any.
NEVER_RUNS=20
mutqueue() { # <main's commit>
  local tp
  tp=$(testspart "$(jq -rn 'now - 6 * 86400 | strftime("%Y-%m-%d")')" 2>/dev/null) && [ -n "$tp" ] || tp=null
  mutorder "$(mutrecs)" "$tp" "$(testacts)" < <(git -C "$MAIN" -c core.quotePath=false ls-tree -r "$1")
}
mutorder() { # <the checks' records> <the snapshot's tests part, or null> <the test actions' records>; main's tree (ls-tree -r) on stdin
  jq -rRn --slurpfile recs <(printf '%s' "$1") --slurpfile tp <(printf '%s' "$2") --slurpfile ta <(printf '%s' "$3") --argjson nr "$NEVER_RUNS" '
    $recs[0] as $recs | $tp[0] as $tp | $ta[0] as $ta | ([inputs | capture("^\\S+ blob (?<b>\\S+)\t(?<p>.*)$")] | map({key: .p, value: .b}) | from_entries) as $b
    | ($recs | map(select(.state == "done" or .state == "failed")) | group_by(.file) | map(max_by(.at) | {key: .file, value: .}) | from_entries) as $last
    | ([($tp.files // [])[] | objects | select(((.runsOnRecord // 0) >= $nr and .caught == 0) or ((.hollow // []) | length) > 0) | .file]
       + [$ta[] | objects | select(.action == "judge" and ((.hollow // []) | length) > 0) | .file]) as $flag
    | [$b | keys[] | select(split("/")[-1] | test("\\.(test|spec)\\.")) | . as $f | $last[$f] as $r
       | select($r == null or any(($r.blobs // {}) | to_entries[]; .value != $b[.key]))
       | {file: $f, at: ($r.at // ""), flag: IN($flag[]; $f)}]
    | sort_by([(if .flag then 0 else 1 end), .at, .file]) | .[].file'
}
# The files asked for (the Board's Mutation check), in $MUTS/asked, one a line, first to last: the front of the idle
# queue. `conveyor.sh mutate ask <test file>...` puts them before those asked earlier, in the order given (a file
# asked again moves there); refused (exit 2), with nothing asked, when one is not a test file of main. A file leaves
# the list when its check starts (mutrun()). An ask starts no check: the idle job (mutnext()) does, when no card needs
# a test slot; the answer says what holds it back now.
mutask() { # <test file>...
  local sha f why
  [ $# -gt 0 ] || { echo "usage: conveyor.sh mutate ask <test file>..." >&2; return 2; }
  sha=$(git -C "$MAIN" rev-parse -q --verify "refs/heads/$BRANCH^{commit}" 2>/dev/null)
  for f in "$@"; do mutfile "$f" "$sha" || { echo "conveyor: $f is not a test file of $BRANCH; nothing asked" >&2; return 2; }; done
  mkdir -p "$MUTS" && { exec {MUTASK}>>"$MUTS/asked.lock"; } 2>/dev/null || { echo "conveyor: the mutation checks' folder could not be made; nothing asked" >&2; return 1; }
  flock "$MUTASK"
  { printf '%s\n' "$@"; cat "$MUTS/asked" 2>/dev/null || :; } | awk '!seen[$0]++' > "$MUTS/asked.new" && mv -f "$MUTS/asked.new" "$MUTS/asked" \
    || { rm -f "$MUTS/asked.new"; exec {MUTASK}>&-; echo "conveyor: the idle queue could not be written; nothing asked" >&2; return 1; }
  exec {MUTASK}>&-
  why=$(mutheld test) || why=''
  echo "conveyor: mutation check asked of $# file(s), at the front of the idle queue. A check starts only when no card needs a test slot${why:+; now $why}."
}
mutunask() { # <test file>: off the asked list
  [ -e "$MUTS/asked" ] && { exec {MUTASK}>>"$MUTS/asked.lock"; } 2>/dev/null || return 0
  flock "$MUTASK"
  grep -vxF -- "$1" "$MUTS/asked" > "$MUTS/asked.new"; mv -f "$MUTS/asked.new" "$MUTS/asked" || rm -f "$MUTS/asked.new"
  exec {MUTASK}>&-
}
# The loop's idle job (`serve`, once a minute; never a card's): when no mutant may start (mutheld()) or a check runs,
# nothing. Else, while no mutant is held back: a check that stopped resumes, or the first file asked for (mutask()),
# or the first file of the queue, is checked, until a check stops or the queue is empty. A queue found empty is not looked at again until main moves
# ($MUTS/idle holds the commit it was empty on).
mutnext() {
  local f sha
  mutheld > /dev/null && return 0
  mkdir -p "$MUTS" && { exec {MUTLOCK}>>"$MUTS/lock"; } 2>/dev/null || return 1
  flock -n "$MUTLOCK" || { exec {MUTLOCK}>&-; return 0; }
  while ! mutheld > /dev/null && sha=$(git -C "$MAIN" rev-parse -q --verify "refs/heads/$BRANCH^{commit}" 2>/dev/null); do
    f=$(mutrecs | jq -r 'map(select(.state == "stopped" or .state == "running")) | min_by(.at) | .file // empty')
    # An asked file that is no longer a test file of main leaves the list unchecked.
    while [ -z "$f" ] && IFS= read -r f 2>/dev/null < "$MUTS/asked" &&[ -n "$f" ]; do mutfile "$f" "$sha" || { mutunask "$f"; f=''; }; done
    if [ -z "$f" ]; then
      [ "$(cat "$MUTS/idle" 2>/dev/null)" != "$sha" ] || break
      f=$(mutqueue "$sha" | head -n 1)
      [ -n "$f" ] || { echo "$sha" > "$MUTS/idle"; break; }
    fi
    mutrun "$f" "$sha" || break
  done
  exec {MUTLOCK}>&-
}
