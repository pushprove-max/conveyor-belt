# SPDX-License-Identifier: Apache-2.0
# `conveyor.sh release-prep <version>` and `conveyor.sh release <version>`: a release, made on the build machine
# (docs/releases.md, Making a release). Only the owner decides a release: the Foreman runs `release` only after the
# owner says yes in chat. One run of either at a time per project ($CARDS/release/lock).
# release-prep runs the pack's whole suite (test.full) on the remote's head of the default branch, in a worktree of
# that commit alone ($CARDS/release/wt), and posts the result on that commit as the commit status
# conveyor/release-suite: success when the suite passed, failure when it did not. The whole-suite runs share one
# record of results a commit ($SUITES, lib/fulltest.sh: each file's ok or fail; release-prep's, release's, Run full
# test suite's and Push landed's). When a run passed every file on that head itself, no test runs and the pass is
# posted. When a run on an ancestor of that head is there (suitebase(): the nearest), it reruns only the files that failed in it, the
# files the commits since add or change, and the files the changed-tests command (test.command, as a card's test step
# runs it) selects for those changes; every other file keeps its ok from that run (suitereuse()). It runs the whole
# suite when there is no such run, or when the commits since change the pack's test settings (test.*) or a file their
# commands name (.conveyor/test-full.sh, the engine's test runner). `release` takes that status's newest
# state, success, as the suite's pass on the commit it releases. The suite runs only when that head holds
# docs/releases/<version>.md in the release notes style (tools/notes-check.sh): `release` releases the commit with the
# notes. When the head has no notes, release-prep has a model write a draft of them in that style (relnotes()), from
# the issues landed and the commits since the newest vX.Y.Z tag (with no tag, an overview from the README and docs), to <state>/release/<version>.md, prints its path and
# stops, for the owner to read and the Foreman to commit as docs/releases/<version>.md; the run after the notes are
# pushed runs the suite. It tags and releases nothing. With Land as pr and Merge PR release (lib/push.sh), it runs on
# the remote's head of the landing branch while that holds a commit the default branch lacks, and `release` checks that
# head (release-prep's pass is on it) and merges the landing pull request only when every check passed (a refused merge
# refuses the release), then makes the release commit on top of the merge and tags that commit.
# Exit 0: passed and posted; 1: the suite failed (failure posted), the head has no notes yet (draft written, nothing
# run), its notes break the style, or a step could not be done; 2: refused at the ask.
# release, in the main checkout, refuses (exit 1), changing nothing and naming each reason, unless all of:
# - the version is higher than the newest vX.Y.Z tag of the remote, and its tag does not exist;
# - the checkout is on the default branch, at the remote's head of it, with no uncommitted change to a tracked file;
# - docs/releases/<version>.md is on that commit, is not empty, and passes the notes style check (tools/notes-check.sh);
# - the privacy check (privacy/check.sh, with the host file's terms file, as gh_write() runs it) finds nothing in the
#   tracked files, nor in the changes since the newest tag: each commit's message and added lines, so a hit a later
#   commit removed is still one (a sign-off or co-author trailer's email that is the commit's own is not: relmessage).
#   With --allow-commit <sha> (any number) --by <who>, the owner's choice: a hit in a named commit already on the
#   remote's default branch is passed over (printed before the release; the record's allowed is {by, commits}); a
#   named commit not on it is refused;
# - the whole suite passed on that commit: the newest conveyor/release-suite status is success (release-prep's
#   pass), else this command runs the suite, as release-prep does, once every other check has passed.
#   With --anyway --by <who> (the owner's choice to release over a red suite), in its place: release-prep's suite ran
#   on that commit and failed (the record's red, below). No suite runs, and no status is posted: the status stays
#   failure. It prints the failed files and cases, and the GitHub release's body is the notes with a "Known test
#   failures" section that says the release went out over a failed suite by <who> and lists them; the record's anyway
#   says the same ({by, sha, files, cases}).
# Then: a commit (made only when either changes) sets plugin.json's version and the marketplace entry's ref to
# v<version>, with no sha; the annotated tag v<version> is made on it; a second commit sets the entry's sha to that
# tagged commit, since a commit cannot hold its own id. The branch and the tag are pushed together (--atomic: if the
# remote's branch moved, neither is, and the commits and the tag are undone here), then the GitHub release is made
# with the notes file as its body (gh release create). Exit 0: released; 1: refused, or a step could not be done.
# Each run of either keeps its record in $CARDS/release/run.json, which the snapshot reads (its suites and release):
# {kind: "release", step (release-prep or release), version, since, ended (null while it runs), state (running, then
# passed (release-prep), released (release), failed (the suite failed), refused (any other refusal) or stopped), sha
# (the commit the suite runs or ran on, null before it), done, failed and cases (the cases ended, those failed and their
# names, as at the suite's end; while it runs the snapshot counts them: suiteprog()), timedout (those of them stopped
# at their time limit, by name), alone (release-prep's red suite: each failed case run alone, as fulljudge() prints it:
# {case, line, runs, verdict: flaky or failed, why}; a suite passed with every failed case flaky has them here only),
# counts (only while those runs alone run: the suite's suiteprog(), which the snapshot shows in their place), moved
# (main moved while the suite
# ran; while it runs the snapshot compares main's head with main), main (main's head as the suite started), reused
# (null for a whole suite; else {sha and time: the run it reused, ran: the files it reran, none when no test ran, kept:
# the passes it kept}), reasons
# (each line the command printed to stderr, its "conveyor: <command>: " taken off), pid (the process whose tree, and
# the processes that carry its mark, `release-run stop` ends), red (a failed release-prep's suite a release may go over: {sha, files, cases}, else null)
# and anyway (a release made over it: red with by, else null) and allowed (a release that passed over hits in named
# commits: {by, commits}, else null)}. A release after a passed release-prep of the same
# version keeps that run's suite (sha, done, failed, cases, alone, moved, reused, since); one after a failed release-prep of
# it keeps that suite too, its files and timedout, and makes red of it; one after a refused release of it keeps that
# one's (all but moved), and its red.
# `conveyor.sh release-run [prep] <version>` is the Board's Release (docs/board.md): the owner's yes, given there. It
# starts release-prep, then, when it passes and prep is not given, release, in the background, and returns (with prep,
# release-prep alone: the Board's Draft notes and Run suite, which release nothing; `release-run anyway <version> --by
# <who>`, the Board's Release anyway: release --anyway alone); their output is in
# $CARDS/release/run.log. That release is told the commit the suite passed on: a main that moved since is refused and
# its record says moved, so it is never tested and released again without the owner's yes. Without prep, when the
# record is a passed release-prep of that version on main's head, main not moved since, it starts release alone, told
# that commit: the suite that passed is used, not run again. `conveyor.sh release-run
# stop` ends the run under way: the processes of that run alone (the tree of the record's pid, and each process that
# carries the run's mark, in whatever process group), never a whole process group, and its record says stopped; it
# returns once the release lock is free (exit 1 when it is not). A run that ends in any other way (a KILL too) ends the
# processes left of it too, so none holds the release lock. Exit 2: refused (a run is already under way; none to stop).
# Sourced by conveyor.sh.
. "$HERE/lib/slots.sh" || exit 1
. "$HERE/lib/prompts.sh" || exit 1
. "$HERE/lib/control.sh" || exit 1
. "$HERE/lib/issues.sh" || exit 1
. "$HERE/lib/pick.sh" || exit 1
. "$HERE/lib/session.sh" || exit 1
. "$HERE/lib/testrun.sh" || exit 1
. "$HERE/lib/push.sh" || exit 1
. "$HERE/lib/followups.sh" || exit 1
. "$HERE/lib/flaky.sh" || exit 1
. "$HERE/lib/fulltest.sh" || exit 1
. "$HERE/lib/run.sh" || exit 1
. "$HERE/lib/machine.sh" || exit 1
. "$HERE/lib/install.sh" || exit 1
names || exit 1
RELHELP="Only the owner decides a release: the Foreman runs conveyor.sh release only after the owner says yes in chat."
RELNOTES_TIMEOUT=600
# The style of the release notes, docs/releases.md (Release notes); tools/notes-check.sh checks its mechanical rules.
RELRULES='- No file, script or function names, no paths, no issue or pull request numbers, no commit hashes, no "Closes", no
  internal unit names. Names a person types or sees (a slash command, a setup question, a setting, a button) are
  allowed.'
RELNOTES='Write the release notes of a new release of this project, from the issues that landed since the last release and
the subjects of its commits, given below. They are for the people who use the project, not for its developers.
- Begin with the line "# VERSION", then one sentence that says what this release is about.
- Then "## " sections named for what a user does or sees (for example: Cards, The Board, In Claude Code, Setup). No
  "###" headings.
- Plain-English bullets about the effect for the user, one change per bullet.
'"$RELRULES"'
- Leave out changes that only touch tests, refactors or tooling, or put them in one plain line if they change nothing
  a user sees.
Answer with the notes alone, in Markdown, and nothing else.'
# The first release (no vX.Y.Z tag yet) has no changes to list: its notes are an overview of the project (relfirst()).
RELFIRST='Write the release notes of the first release of this project: an overview of what it does, from its README and
its docs, given below. There is no earlier release, so list no changes. They are for the people who use the project,
not for its developers.
- Begin with the line "# VERSION", then one sentence that says what the project is.
- Then "## " sections, one for each area of the project, named as the README names its sections. No "###" headings.
- Plain-English bullets, each about one thing a user can do or see. Say nothing the README and the docs do not say.
'"$RELRULES"'
Answer with the notes alone, in Markdown, and nothing else.'
# The notes draft (<file>), written by a model (askmodel) from the issues the commits since <last tag> up to <commit>
# name ("(#N)" at a subject's end, or a "Closes #N" line: their titles and bodies, as gh reads them) and those commits'
# subjects, merges left out, each with its trailing (#N) taken off. An issue gh cannot read is left out, with a
# warning; its commit's subject is still given. With no last tag (the first release): from <commit>'s README and docs
# alone (relfirst()), no commit or issue. Fails, with why on stdout, when the model gives no notes.
relnotes() { # <version> <last tag, or empty> <commit> <file>
  local subj ns n j iss='[]' p d rc s c
  if [ -z "$2" ]; then p=$(relfirst "$1" "$3")
  else
    subj=$(git log --no-merges --format=%s "$2..$3" | sed -E 's/ \(#[0-9]+\)$//') && ns=$(git log --no-merges --format=%B "$2..$3") || { echo "the commits could not be read"; return 1; }
    for n in $(grep -oE '(\(#[0-9]+\)$|^Closes #[0-9]+)' <<<"$ns" | grep -oE '[0-9]+' | sort -un); do
      j=$(timeout 60 gh issue view "$n" --json number,title,body < /dev/null 2>/dev/null) && iss=$(jq -c --argjson i "$j" '. + [$i]' <<<"$iss" 2>/dev/null) \
        || echo "conveyor: release-prep: issue #$n could not be read; the notes are written without it" >&2
    done
    p=${RELNOTES//VERSION/$1}$'\n\n'$(jq -r --arg s "$subj" '"# The issues that landed\n\n" + (map("## \(.title // "")\n\n\((.body // "")[0:4000])\n") | join("\n"))
      + "\n# The commit subjects\n\n" + $s' <<<"$iss") || { echo "the issues could not be read"; return 1; }
  fi
  c=$(ctl 2>/dev/null) || c=''
  d=$(mktemp -d) || { echo "no scratch folder"; return 1; }
  s=$(askmodel "$d" "$RELNOTES_TIMEOUT" medium "$c" "$p"); rc=$?
  [ -z "$s" ] || { rm -rf "$d"; echo "$s"; return 1; }
  [ "$rc" = 0 ] && [ -n "$(tr -d '[:space:]' < "$d/answer" 2>/dev/null)" ] && cp "$d/answer" "$4" \
    || { rm -rf "$d"; echo "the model gave no notes (exit $rc; 124 is the ${RELNOTES_TIMEOUT}s timeout)"; return 1; }
  rm -rf "$d"
}
# The prompt of the first release's notes: the overview style, then <commit>'s README.md (its first 12000 bytes) and
# each Markdown page directly in docs/ (its first 6000), each under a "# <path>" heading.
relfirst() { # <version> <commit>
  local f p=${RELFIRST//VERSION/$1}
  p+=$'\n\n# README.md\n\n'$(git show "$2:README.md" 2>/dev/null | head -c 12000)
  while IFS= read -r f; do
    p+=$'\n\n# '"$f"$'\n\n'$(git show "$2:$f" | head -c 6000)
  done < <(git ls-tree --name-only "$2" docs/ 2>/dev/null | grep '\.md$')
  printf '%s\n' "$p"
}
# The release lock (its descriptor RELLK), held until the command ends. 1: it could not be made; 2: another run holds it.
RELLK=''
rellock() { # <command name>
  mkdir -p "$CARDS/release" && { exec {RELLK}>>"$CARDS/release/lock"; } 2>/dev/null || { echo "conveyor: $1: its lock could not be made; nothing run" >&2; return 1; }
  flock -n "$RELLK" || { echo "conveyor: $1: release-prep or release is already running; this one is not started" >&2; return 2; }
}
# The run's record (above), begun once the lock is held. RELSTARTED says it was, so a run refused before it (or at the
# lock) leaves the record of the one under way as it is.
RELRUN=$CARDS/release/run.json
RELSTARTED=''
relrec() { jq -c "$@" "$RELRUN" > "$RELRUN.new" 2>/dev/null && mv -f "$RELRUN.new" "$RELRUN"; } # <jq arguments, the filter first>
relstart() { # <command name> <version>
  local was=null
  # release keeps the suite's commit and cases from release-prep's pass of its version, or from a release of it
  # refused since (a retry takes the pass from the status and runs no suite). From release-prep's failed suite of its
  # version: that suite, and red, the failed run `release --anyway` may go over, kept through a refused release.
  [ "$1" != release ] || was=$(jq -ce --arg v "$2" 'select(.version == $v and .sha != null) | if .step == "release-prep" and .state == "passed" then {since, sha, done, failed, cases, moved, reused, alone: (.alone // [])}
    elif .step == "release-prep" and .state == "failed" then {since, sha, done, failed, cases, moved, reused, files, timedout, alone: (.alone // []), red: {sha, files: (.files.failed // []), cases}}
    elif .step == "release" and .state == "refused" then {since, sha, done, failed, cases, reused, red} else empty end' "$RELRUN" 2>/dev/null) || was=null
  jq -cn --arg s "$1" --arg v "$2" --arg t "$(clock)" --argjson p "${CONVEYOR_RELEASE_PID:-$$}" --argjson w "$was" \
    '{kind: "release", step: $s, version: $v, since: $t, ended: null, state: "running", sha: null, done: 0, failed: 0, cases: [], alone: [], moved: false, reused: null, reasons: [], pid: $p, red: null, anyway: null, allowed: null} + $w' > "$RELRUN.new" \
    && mv -f "$RELRUN.new" "$RELRUN" && RELSTARTED=1
  # Each process the run starts carries its mark (relprocs()). The run's end ends them all: the suite's runner
  # (timeout) is a process group of its own, which a signal to this process never reaches, and each holds the release
  # lock it inherited. A KILL runs no trap, so a watcher, without the lock, ends them once the run's pid has ended.
  export CONVEYOR_RELEASE_RUN="${CONVEYOR_RELEASE_PID:-$$}"
  ( [ -z "$RELLK" ] || exec {RELLK}>&-
    while kill -0 "$CONVEYOR_RELEASE_RUN" 2>/dev/null; do sleep 1; done # sleep: the watcher's pause between two checks
    relreap "$$" "$CONVEYOR_RELEASE_RUN" "$BASHPID" ) < /dev/null > /dev/null 2>&1 &
  trap 'relreap $$ "$CONVEYOR_RELEASE_RUN"' EXIT; trap 'exit 143' TERM; trap 'exit 130' INT; trap 'exit 129' HUP
  unset CONVEYOR_RELEASE_PID # the suite's own commands are no part of this run's record
}
# The processes of a release run, one a line: <pid> and those under it, and each that carries the run's <mark>
# (CONVEYOR_RELEASE_RUN=<mark> in its environment, relstart()), which a process group or session of its own, or a
# parent that ended, takes out from under <pid>. Never <pid left out> (default this process), nor
# one that has ended (a zombie), nor the process that lists them and its ps (which carries the mark when it does).
# Called alone in a command substitution ($(relprocs ...)), whose subshell is the process that lists them, and its ps
# exec'd in its own substitution's subshell, so that the ps's parent is that process. Else the scan found a process of
# its own that carries the mark (a pipe's other side, or a ps one subshell further down), and a reap from a process of
# the run (the run's own end, its watcher) ran all its KILL rounds (relreap()). What it starts (ps, awk, sort) carries
# no mark, so another reap at the same time (the stop's, the run's own end's) does not find it as a process of the run.
relprocs() { # <pid> <mark> [<pid left out>]
  local t e me=$BASHPID x=${3:-$$}
  unset CONVEYOR_RELEASE_RUN # in this command substitution's subshell alone
  t=$(exec ps -A -o pid= -o ppid= -o stat= 2>/dev/null); e=$(exec ps axeww -o pid= -o ppid= -o command= 2>/dev/null)
  { awk -v r="$1" -v me="$me" -v x="$x" '{ k[$2] = k[$2] " " $1; a[$1] = ($3 !~ /Z/) } END { q[1] = r; n = 1
    for (i = 1; i <= n; i++) { if (q[i] == me) continue; if (a[q[i]] && q[i] != x) print q[i]; m = split(k[q[i]], c, " "); for (j = 1; j <= m; j++) q[++n] = c[j] } }' <<<"$t"
    awk -v k=" CONVEYOR_RELEASE_RUN=$2 " -v me="$me" -v x="$x" '$1 != me && $1 != x && $2 != me && index($0 " ", k) { print $1 }' <<<"$e"; } | sort -u
}
# A release run ended (relprocs()'s arguments): each of its processes told to end, then killed 10 s later if they
# have not, and killed again while one is left (one started meanwhile, or one still ending), for up to 2 s. Its sleeps
# carry no mark either (relprocs()).
relreap() { # <pid> <mark> [<pid left out>]
  local ps i
  ps=$(relprocs "$@") && [ -n "$ps" ] || return 0
  # shellcheck disable=SC2086 # one pid a word
  kill -TERM $ps 2>/dev/null
  # shellcheck disable=SC2086
  for ((i = 0; i < 100; i++)); do kill -0 $ps 2>/dev/null || break; env -u CONVEYOR_RELEASE_RUN sleep 0.1; done
  for ((i = 0; i < 20; i++)); do
    ps=$(relprocs "$@") && [ -n "$ps" ] || return 0
    # shellcheck disable=SC2086
    kill -KILL $ps 2>/dev/null; env -u CONVEYOR_RELEASE_RUN sleep 0.1
  done
}
# The record at the command's end: its state, and each line it printed to stderr (<file>) as a reason.
relend() { # <exit> <stderr file>
  [ -n "$RELSTARTED" ] || return 0
  relrec --arg t "$(clock)" --argjson rc "$1" --rawfile e "$2" '.ended = $t
    | .reasons = [$e | split("\n")[] | select(. != "") | sub("^conveyor: [a-z-]+: (refused, nothing tagged or released: )?"; "")]
    | .state = (if $rc == 0 then (if .step == "release" then "released" else "passed" end) elif .state == "failed" then "failed" else "refused" end)'
}
# The command, its record kept; its stderr is printed once it ends.
relrun() { # <function> <version>
  local e rc
  e=$(mktemp) || { echo "conveyor: $1: no scratch file; nothing run" >&2; return 1; }
  "$1" "$2" 2> "$e"; rc=$?
  cat "$e" >&2; relend "$rc" "$e"; rm -f "$e"
  return $rc
}
# The newest vX.Y.Z tag, after the remote's branch and tags are fetched.
# relmessage <commit>: the commit's message for the privacy check, with the email taken out of each Signed-off-by: or
# Co-authored-by: trailer whose last <email> is the commit's own author or committer email (case aside), which the
# commit already shows in its author fields. The rest of each such line, and every other email, is still checked.
relmessage() {
  local m; m=$(git log -1 --format='%ae%n%ce' "$1") || return 1
  git log -1 --format=%B "$1" | RELA=${m%%$'\n'*} RELC=${m#*$'\n'} awk '
    BEGIN { a = tolower(ENVIRON["RELA"]); c = tolower(ENVIRON["RELC"]) }
    tolower($0) ~ /^(signed-off-by|co-authored-by):/ && match($0, /<[^<>]*>[[:space:]]*$/) {
      e = substr($0, RSTART + 1, RLENGTH - 1); sub(/>[[:space:]]*$/, "", e); e = tolower(e)
      if (e != "" && (e == a || e == c)) $0 = substr($0, 1, RSTART - 1)
    }
    { print }'
}
lasttag() { git tag -l 'v*' | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -n 1; }
# The whole suite (test.full) on <commit>, in a worktree of it alone, its result posted on it as conveyor/release-suite,
# its files' results and times kept for the Tests page (suiterec(), lib/testrun.sh) and its results in the whole-suite
# record every whole-suite run shares (suitekeep(), lib/fulltest.sh). release-prep reuses that record (suitereuse()):
# with a pass of every file on <commit> itself (a full test run's, or Push landed's) it runs no test and posts the pass;
# with results on an ancestor it runs only some files (the suite's command is told the list by the file
# CONVEYOR_SUITE_FILES names), its record's reused naming that run and the files rerun; the others keep that run's ok.
# A red suite of release-prep: each failed case is run alone FULL_ALONE times on <commit> and judged as the full test
# judges it (fulljudge(), lib/fulltest.sh), the record's alone keeping each with its runs alone and verdict. One that
# passed every run alone is flaky (the flaky-test record, its source "release <version> <commit>") and blocks nothing:
# when every failed case is flaky, the suite passes, and its status and the record (cases [], failed 0) say so. Any
# other blocks the release.
# 0: passed and posted; 1: failed (failure posted), or a step could not be done; 2: the pack names no test.full.
relsuite() { # <command name> <commit>
  local n=$1 sha=$2 cmd wt=$CARDS/release/wt out rc sr state desc m0 m1 p l='' u=null f al='[]' fl=''
  packget test.full cmd || return 1
  [ -n "$cmd" ] || { echo "conveyor: $n: the pack names no full test suite (test.full); nothing run" >&2; return 2; }
  # main as the suite starts: a card that lands while it runs moves it (the record's moved).
  m0=$(git rev-parse -q --verify "refs/heads/$BRANCH^{commit}" 2>/dev/null)
  relrec --arg s "$sha" --arg m "$m0" '.sha = $s | .done = 0 | .failed = 0 | .cases = [] | .alone = [] | .moved = false | .reused = null | .main = (if $m == "" then null else $m end)'
  out=$({ git worktree remove --force "$wt" 2>/dev/null; rm -rf "$wt" "$wt".*; git worktree prune
    git worktree add -q --detach "$wt" "$sha" && deps "$wt"; } 2>&1 < /dev/null) || {
    git worktree remove --force "$wt" 2>/dev/null; echo "conveyor: $n: the worktree of ${sha:0:12} could not be made; nothing run: ${out:0:600}" >&2; return 1; }
  rc=1
  if [ "$n" = release-prep ]; then
    l=$(suitereuse "$wt" "$sha"); rc=$?
    [ $rc != 2 ] || { git worktree remove --force "$wt" 2>/dev/null; echo "conveyor: $n: the worktree of ${sha:0:12} could not be put back on it after the changed-tests selection; nothing run" >&2; return 1; }
  fi
  if [ $rc = 3 ]; then
    # A pass of every file on this very commit (a full test run's, or Push landed's): nothing runs.
    rc=0; u=$(jq -c '{sha, time, ran: [], kept: (.files | length)}' <<<"$l")
    echo "conveyor: $n: reuses the green run of $(jq -r .time <<<"$l") on ${sha:0:12}; no test runs"
  else
    if [ $rc = 0 ]; then
      echo "conveyor: $n: reruns the files that failed or changed since the suite run on $(jq -r '.sha[0:12]' <<<"$l") ($(wc -l < "$wt.files") listed) and reuses its other passes"
      CONVEYOR_SUITE_FILES=$wt.files tests "$wt" test.full; rc=$?
    # A whole run (not a rerun of some files) makes a test map that is due again from its coverage (lib/testmap.sh
    # mapcovon(), maprefresh()).
    else l=''; mapcovon "$wt" || :; tests "$wt" test.full; rc=$?; mapcovoff; fi
    suiterec "$wt" release "$sha"
    u=$(suitekeep "$wt" "$sha" "$rc" "$n" "$l") && [ -n "$u" ] || u=null
    # A run with some files only whose results could not be kept proves nothing of the others: it is no pass.
    [ -z "$l" ] || [ "$u" != null ] || [ $rc != 0 ] || { rc=1; echo "conveyor: $n: the rerun's results could not be read, so the passes of $(jq -r '.sha[0:12]' <<<"$l") are not reused" >&2; }
  fi
  relrec --slurpfile u <(printf '%s' "$u") '.reused = $u[0]'
  # The cases its runner named as ended; a red run whose runner named no failed case has those its output names
  # (testfails()), each named as fulljudge() names it.
  p=$(suiteprog "$wt")
  [ $rc = 0 ] || [ "$(jq .failed <<<"$p")" != 0 ] || p=$(testfails "$wt.test" "$rc" test.full | jq -c --argjson p "$p" --arg cmd "$cmd" \
    '$p + {cases: [.files[]? | .file as $f | if (.cases // []) == [] then $f else .cases[] | if $f == $cmd or $f == "" then .name else "\($f): \(.name)" end end] | unique}
      | .failed = (.cases | length)' 2>/dev/null) || p=$(suiteprog "$wt")
  sr=$rc
  if [ $rc != 0 ] && [ "$n" = release-prep ]; then
    f=$(testfails "$wt.test" "$rc" test.full) || f='{"files":[]}'
    # A file kept from the reused run passed: each case run alone is told so, as of a file that passed in this run.
    [ -z "$l" ] || f=$(jq -c --slurpfile l <(printf '%s' "$l") --rawfile run "$wt.files" '$l[0] as $l | .passed = ((.passed // []) + ([$l.files | to_entries[] | select(.value == "ok") | .key] - ($run | split("\n"))))' <<<"$f")
    # Each run alone below runs in this worktree, so it clears the suite's log folder and output: the record keeps the
    # suite's counts while they run (the Release panel's progress: lib/snapshot.sh suites()), and the suite's log
    # folder and output are put aside and back, so a failed release points to the suite's output, not a run alone's.
    relrec --argjson p "$p" '.counts = $p'
    rm -rf "$wt.suitelog" "$wt.suitetest"; mv "$wt.testlog" "$wt.suitelog" 2>/dev/null; mv "$wt.test" "$wt.suitetest" 2>/dev/null
    al=$(fulljudge "$wt" "$sha" "$cmd" "$f" "release $(jq -r .version "$RELRUN")") && jq -e 'type == "array"' <<<"$al" > /dev/null || al='[]'
    rm -rf "$wt.testlog" "$wt.test"; mv "$wt.suitelog" "$wt.testlog" 2>/dev/null; mv "$wt.suitetest" "$wt.test" 2>/dev/null
    # Every failed case flaky passes the suite: only when the cases judged are at least those its runner named as failed,
    # so a failure the output names no case of is never passed over.
    if jq -e --argjson p "$p" 'length > 0 and length >= $p.failed and all(.verdict == "flaky")' <<<"$al" > /dev/null; then
      rc=0; fl=$(jq -r 'map(.case) | join(", ")' <<<"$al")
      p=$(jq -c '.failed = 0 | .cases = [] | .timedout = [] | .files.failed = []' <<<"$p")
      echo "conveyor: $n: every failed case passed alone $FULL_ALONE of $FULL_ALONE on ${sha:0:12}, so the suite passes; judged flaky: $fl"
    else
      jq -r '.[] | "conveyor: '"$n"': \(.case): \(.verdict): runs alone \(.runs | join(", "))\(if .why then "; " + .why else "" end)"' <<<"$al" >&2
    fi
  fi
  m1=$(git rev-parse -q --verify "refs/heads/$BRANCH^{commit}" 2>/dev/null)
  relrec --argjson p "$p" --argjson mv "$([ "$m0" = "$m1" ] && echo false || echo true)" --arg st "$([ $rc = 0 ] && echo passed || echo failed)" --argjson al "$al" \
    '. + $p | .moved = $mv | .state = $st | .alone = $al | del(.counts)'
  [ "$m0" = "$m1" ] || echo "conveyor: $n: $BRANCH moved while the suite ran, from ${m0:0:12} to ${m1:0:12}: a card landed; the suite tested ${sha:0:12}"
  # The test map is of the suite run alone: a red one, though its failed cases then passed alone, refreshes none.
  if [ $sr = 0 ]; then maprefresh "$wt" || :; else mapstop "$wt" "the release's whole run failed"; fi
  git worktree remove --force "$wt" 2>/dev/null
  if [ $rc = 0 ] && [ "$u" != null ] && [ "$(jq '.ran | length' <<<"$u")" = 0 ]; then
    state=success desc=$(jq -r '"The whole suite (test.full) passed on the build machine: reused the green run of \(.time) on \(.sha[0:12])"' <<<"$u")
  elif [ $rc = 0 ] && [ "$u" != null ]; then
    state=success desc=$(jq -r '"The whole suite (test.full) passed on the build machine: reran \(.ran | length) files, reused \(.kept) passed files from \(.sha[0:12])"' <<<"$u")
  elif [ $rc = 0 ]; then state=success desc="The whole suite (test.full) passed on the build machine"
  else state=failure desc="The whole suite (test.full) failed on the build machine (exit $rc)"; fi
  # A status's description is at most 140 characters (GitHub): the record's alone names every case judged flaky.
  [ -z "$fl" ] || { desc+="; judged flaky: $fl"; desc=${desc:0:140}; }
  gh_write api -X POST "repos/{owner}/{repo}/statuses/$sha" -f "state=$state" -f context=conveyor/release-suite -f "description=$desc" > /dev/null \
    || { echo "conveyor: $n: the status of ${sha:0:12} could not be posted (the suite $([ $rc = 0 ] && echo passed || echo failed))" >&2; return 1; }
  if [ $rc = 0 ]; then echo "conveyor: $n: the whole suite passed on ${sha:0:12}; its status is posted"
  else echo "conveyor: $n: the whole suite failed on ${sha:0:12} (exit $rc; its output is in $wt.test); a failing status is posted" >&2; return 1; fi
}
releaseprep() { # <version>
  local v=$1 cmd sha last d out
  packget test.full cmd || return 1
  [ -n "$cmd" ] || { echo "conveyor: release-prep: the pack names no full test suite (test.full); nothing run" >&2; return 2; }
  rellock release-prep || return $?
  relstart release-prep "$v"
  # The commit `release` releases is the remote's head of the branch, and the tags are the remote's.
  git fetch -q "$REMOTE" "+refs/heads/$BRANCH:refs/remotes/$REMOTE/$BRANCH" 'refs/tags/v*:refs/tags/v*' < /dev/null \
    && sha=$(git rev-parse -q --verify "refs/remotes/$REMOTE/$BRANCH^{commit}") || { echo "conveyor: release-prep: $REMOTE/$BRANCH could not be read; nothing run" >&2; return 1; }
  # Merge PR release (prmergerule(), lib/push.sh): the cards wait in the pull request of Land as pr, which `release`
  # merges before it tags, so the suite runs on the head of LANDING while that holds a commit the default branch lacks.
  if [ "$(prmergerule 2>/dev/null)" = release ] && [ "$(landas 2>/dev/null)" = pr ] \
    && git fetch -q "$REMOTE" "+refs/heads/$LANDING:refs/remotes/$REMOTE/$LANDING" < /dev/null 2>/dev/null \
    && out=$(git rev-parse -q --verify "refs/remotes/$REMOTE/$LANDING^{commit}") && ! git merge-base --is-ancestor "$out" "$sha"; then
    sha=$out; echo "conveyor: release-prep: the suite runs on $REMOTE/$LANDING (${sha:0:12}), which release merges before it tags"
  fi
  last=$(lasttag)
  # `release` releases the remote's head and reads the status of that commit, so the suite runs only on a head that
  # holds the notes, in the notes style: a status posted on another commit is on one the release does not use.
  if [ -n "$(git show "$sha:docs/releases/$v.md" 2>/dev/null | tr -d '[:space:]')" ]; then
    out=$(git show "$sha:docs/releases/$v.md" | "$HERE/tools/notes-check.sh" - "docs/releases/$v.md") \
      || { echo "conveyor: release-prep: docs/releases/$v.md on ${sha:0:12} breaks the release notes style, so the suite is not run and no status is posted: $(head -n 10 <<<"$out" | paste -sd ';' -)" >&2; return 1; }
    echo "conveyor: release-prep: ${sha:0:12} holds docs/releases/$v.md"
    relsuite release-prep "$sha"; return
  fi
  d=${STATE%/*}/release/$v.md
  mkdir -p "${d%/*}" && rm -f "$d" && out=$(relnotes "$v" "$last" "$sha" "$d") || { echo "conveyor: release-prep: the notes draft could not be written: $out; nothing run" >&2; return 1; }
  out=$("$HERE/tools/notes-check.sh" "$d") || out=" The draft breaks the release notes style: $(head -n 10 <<<"$out" | paste -sd ';' -)."
  local from="from the issues and commits since $last"; [ -n "$last" ] || from='an overview from the README and docs, as no release is tagged yet'
  echo "conveyor: release-prep: the notes draft, $from, is $d.$out ${sha:0:12} ($REMOTE/$BRANCH) has no docs/releases/$v.md, so the suite is not run and no status is posted: read the draft, edit it as needed, commit it as docs/releases/$v.md on $BRANCH, push it, and run release-prep $v again" >&2
  return 1
}
RELBY='' RELANY='' RELALLOW=() # release [--anyway] [--allow-commit <sha>]... --by <who>: the owner's choices, and who made them
release() { # <version>
  local v=$1 sha last c rc out terms name t state notes=docs/releases/$1.md why=() hits=() red='' body='' known='' a f allow=() passed=()
  local P=.claude-plugin/plugin.json M=.claude-plugin/marketplace.json tested=${CONVEYOR_RELEASE_SHA-} at=refs/remotes/$REMOTE/$BRANCH pr=''
  [ -z "${CONVEYOR_RELEASE_SHA+x}" ] || [ -n "$tested" ] || tested=none # set by the Board with no commit: nothing passed
  unset CONVEYOR_RELEASE_SHA
  rellock release || return 1
  relstart release "$v"
  git fetch -q "$REMOTE" "+refs/heads/$BRANCH:refs/remotes/$REMOTE/$BRANCH" 'refs/tags/v*:refs/tags/v*' < /dev/null \
    && sha=$(git rev-parse -q --verify 'HEAD^{commit}') \
    || { echo "conveyor: release: refused, nothing tagged or released: $REMOTE/$BRANCH or the checkout's HEAD could not be read" >&2; return 1; }
  # Merge PR release (prmergerule(), lib/push.sh): with the pull request of Land as pr open, what is released is the head
  # of LANDING it merges (release-prep ran the suite there), and every check below, the suite's too, reads that commit.
  # The pull request is merged only once none of them refuses (prmerge(), below): a refused release merges nothing. With
  # origin's default branch holding a commit LANDING lacks, the merge would hold files no check read: refused.
  if [ "$(prmergerule 2>/dev/null)" = release ] && [ "$(landas 2>/dev/null)" = pr ]; then
    out=$(landingprs) && pr=$(jq -er '.[0].number // ""' <<<"$out" 2>/dev/null) \
      || { echo "conveyor: release: refused, nothing tagged or released: the open pull request from $LANDING could not be read: ${out:0:600}" >&2; return 1; }
    if [ -n "$pr" ]; then
      git fetch -q "$REMOTE" "+refs/heads/$LANDING:refs/remotes/$REMOTE/$LANDING" < /dev/null && at=refs/remotes/$REMOTE/$LANDING \
        || { echo "conveyor: release: refused, nothing tagged or released: $REMOTE/$LANDING could not be read" >&2; return 1; }
      git merge-base --is-ancestor "refs/remotes/$REMOTE/$BRANCH" "$at" \
        || why+=("$REMOTE/$BRANCH holds a commit $LANDING lacks, so the merge of pull request #$pr would hold files no check read")
    fi
  fi
  [ "$(git symbolic-ref -q HEAD)" = "refs/heads/$BRANCH" ] && [ "$sha" = "$(git rev-parse -q --verify "$at^{commit}")" ] \
    || why+=("the checkout is not on $BRANCH at the head of ${at#refs/remotes/}")
  [ -z "$(git status --porcelain --untracked-files=no)" ] || why+=("the checkout has uncommitted changes")
  # The Board's Release (releasego()): the commit its release-prep tested. A card landed since: refused, the record
  # moved, for the owner to press Run again on the new main.
  if [ -n "$tested" ] && [ "$tested" != "$sha" ]; then
    why+=("$BRANCH moved while the suite ran, from ${tested:0:12} to ${sha:0:12}: a card landed; press Run again on the new main")
    relrec '.moved = true'
  fi
  last=$(lasttag)
  if git rev-parse -q --verify "refs/tags/v$v" > /dev/null; then why+=("the tag v$v already exists")
  elif [ -n "$last" ] && [ "$(printf '%s\n' "${last#v}" "$v" | sort -V | tail -n 1)" != "$v" ]; then why+=("the version $v is not higher than the newest release, $last")
  fi
  if [ -z "$(git show "$sha:$notes" 2>/dev/null | tr -d '[:space:]')" ]; then why+=("there are no release notes: $notes is missing or empty on ${sha:0:12}")
  elif ! out=$(git show "$sha:$notes" | "$HERE/tools/notes-check.sh" - "$notes"); then
    why+=("the release notes break the release notes style: $(head -n 10 <<<"$out" | paste -sd ';' -)")
  fi
  # --allow-commit: a commit named by the owner whose hits the commit check passes over, only when it is already on
  # $REMOTE/$BRANCH, or the LANDING head released (pushed history, which only a rewrite could change). The tracked-files check passes over nothing.
  for a in "${RELALLOW[@]}"; do
    if ! f=$(git rev-parse -q --verify "$a^{commit}"); then why+=("--allow-commit $a: there is no such commit")
    elif ! git merge-base --is-ancestor "$f" "$at"; then why+=("--allow-commit $a: ${f:0:12} is not on ${at#refs/remotes/}, so its hits are not passed over")
    else allow+=("$f"); fi
  done
  terms=$(termsfile)
  if [ -z "$terms" ] && termsnamed; then why+=("the host file's terms file cannot be read, so the privacy check cannot be made")
  else
    out=$(git ls-files -z | xargs -0 "$HERE/privacy/check.sh" ${terms:+--terms "$terms"} 2>&1) \
      || why+=("the privacy check finds something in the tracked files, or cannot read one: $(head -n 5 <<<"$out" | paste -sd ';' -)")
    if [ -n "$last" ]; then
      while read -r c; do
        { relmessage "$c"; git show --format= --no-color --no-ext-diff --text -U0 --diff-merges=first-parent "$c" | grep '^+' | grep -vE '^\+\+\+ (b/|/dev/null)'; } \
          | "$HERE/privacy/check.sh" ${terms:+--terms "$terms"} - > /dev/null; rc=${PIPESTATUS[1]} # the check's own: grep finding no added line is no hit
        if [ "$rc" = 1 ] && [[ " ${allow[*]} " == *" $c "* ]]; then passed+=("$c"); continue; fi
        [ "$rc" = 0 ] || hits+=("${c:0:12}$([ "$rc" = 1 ] || echo ' (the check failed)')")
      done < <(git rev-list "$last..$sha")
      [ ${#hits[@]} = 0 ] || why+=("the privacy check finds something in commits since $last: ${hits[*]} (run conveyor/privacy/check.sh on each to see where)")
    fi
  fi
  name=$(jq -r .name "$P" 2>/dev/null) && [ -n "$(jq --arg n "$name" '.plugins[] | select(.name == $n)' "$M" 2>/dev/null)" ] \
    || why+=("$M has no entry for the plugin $P names")
  # Over a red suite: only release-prep's failed suite of this version on this very commit (the record's red).
  if [ -n "$RELANY" ]; then
    red=$(jq -ce '.red | objects' "$RELRUN" 2>/dev/null) || red=''
    if [ -z "$red" ]; then why+=("--anyway: release-prep's suite of $v did not run and fail on ${sha:0:12}, so there is no failed suite to release over: run release-prep $v")
    elif [ "$(jq -r .sha <<<"$red")" != "$sha" ]; then
      why+=("--anyway: release-prep's suite of $v failed on $(jq -r '.sha[0:12]' <<<"$red"), not on ${sha:0:12}: $BRANCH moved since; run release-prep $v again"); red=''
    else
      # The section the GitHub release's body gets: who, and the failed files and cases. It is published, so the
      # privacy check reads it here, before anything is tagged or pushed (gh_write would refuse it after the push).
      known=$(jq -r --arg v "$v" --arg by "$RELBY" '"\n## Known test failures\n\n\($v) was released over a failed suite by \($by): the whole suite failed on \(.sha[0:12]).\n"
        + (if .files == [] then "" else "\nFailed files:\n\n" + (.files | map("- \(.)\n") | join("")) end)
        + (if .cases == [] then "" else "\nFailed cases:\n\n" + (.cases | map("- \(.)\n") | join("")) end)' <<<"$red") \
        || why+=("--anyway: the Known test failures section could not be made from release-prep's record")
      if [ -n "$known" ] && ! { [ -z "$terms" ] && termsnamed; }; then
        out=$(printf '%s\n' "$known" | "$HERE/privacy/check.sh" ${terms:+--terms "$terms"} - 2>&1) \
          || why+=("--anyway: the privacy check finds something in --by or the failed files and cases, which the release notes would publish: $(head -n 5 <<<"$out" | paste -sd ';' -)")
      fi
    fi
  fi
  if [ ${#why[@]} != 0 ]; then printf 'conveyor: release: refused, nothing tagged or released: %s\n' "${why[@]}" >&2; return 1; fi
  [ ${#passed[@]} = 0 ] || echo "conveyor: release: the privacy check passes over its hits in ${passed[*]}, on $REMOTE/$BRANCH, by $RELBY"
  # The suite last: it takes the longest, and a refusal above needs none of it.
  if [ -n "$red" ]; then
    # No suite runs and no status is posted: conveyor/release-suite stays the failure release-prep posted.
    echo "conveyor: release: $v goes out over the failed suite on ${sha:0:12}, by $RELBY; $(jq -r '"failed files: \(if .files == [] then "none named" else .files | join(", ") end); failed cases: \(if .cases == [] then "none named" else .cases | join(", ") end)"' <<<"$red")"
  else
    state=$(timeout 60 gh api "repos/{owner}/{repo}/commits/$sha/statuses?per_page=100" < /dev/null 2>/dev/null \
      | jq -r '[.[] | select(.context == "conveyor/release-suite")][0].state // "none"' 2>/dev/null)
    if [ "$state" = success ]; then
      # The record names the commit the pass is of; its cases are known only from a run of that commit kept above.
      relrec --arg s "$sha" 'if .sha == $s then . else .sha = $s | .done = 0 | .failed = 0 | .cases = [] | .reused = null end'
      echo "conveyor: release: the whole suite passed on ${sha:0:12} (release-prep's status); it is not run again"
    else relsuite release "$sha" || { echo "conveyor: release: refused, nothing tagged or released: the whole suite did not pass on ${sha:0:12}" >&2; return 1; }; fi
  fi
  # The suite takes long: a checkout that moved meanwhile would tag commits no check above read.
  [ "$(git rev-parse -q --verify HEAD)" = "$sha" ] && [ -z "$(git status --porcelain --untracked-files=no)" ] \
    || { echo "conveyor: release: refused, nothing tagged or released: the checkout moved or changed while the suite ran" >&2; return 1; }
  # Merge PR release: every check passed on the head of LANDING, so the pull request is merged now, main here brought
  # to the merge (exit 3: an issue or main not brought in line after it, which the check below finds for main), and
  # the release is made on the merge, which must hold the files checked.
  if [ -n "$pr" ]; then
    out=$(prmerge release 2>&1); rc=$?
    [ $rc = 0 ] || [ $rc = 3 ] || { echo "conveyor: release: refused, nothing tagged or released: the landing pull request was not merged: ${out:0:600}" >&2; return 1; }
    printf '%s\n' "$out"
    t=$(git rev-parse -q --verify 'HEAD^{commit}') && git merge-base --is-ancestor "$sha" "$t" && [ "$(git rev-parse "$t^{tree}")" = "$(git rev-parse "$sha^{tree}")" ] \
      && [ -z "$(git status --porcelain --untracked-files=no)" ] \
      || { echo "conveyor: release: refused, nothing tagged or released: pull request #$pr is merged, but the checkout is not at a merge holding the files checked on ${sha:0:12}" >&2; return 1; }
    sha=$t
  fi
  # A step that fails undoes what was made here: the tag, the commits, and the two files' changes, nothing else.
  relundo() { git tag -d "v$v" > /dev/null 2>&1; git reset -q "$sha" && git checkout -q "$sha" -- "$P" "$M"; }
  relset() { jq "${@:2}" "$1" > "$1.new" && mv "$1.new" "$1"; } # <file> <jq arguments>
  relset "$P" --arg v "$v" '.version = $v' && relset "$M" --arg n "$name" --arg r "v$v" '(.plugins[] | select(.name == $n) | .source) |= (.ref = $r | del(.sha))' \
    && { git diff --quiet -- "$P" "$M" || git commit -q -m "Release $v" -- "$P" "$M"; } && git tag -a "v$v" -m "Release $v" && t=$(git rev-parse HEAD) \
    && relset "$M" --arg n "$name" --arg s "$t" '(.plugins[] | select(.name == $n) | .source.sha) = $s' \
    && git commit -q -m "Release $v: the marketplace pins v$v at its commit" -- "$M" \
    || { relundo; echo "conveyor: release: the release commits or the tag could not be made; they are undone, nothing pushed" >&2; return 1; }
  git push -q --atomic "$REMOTE" "HEAD:refs/heads/$BRANCH" "refs/tags/v$v" < /dev/null \
    || { relundo; echo "conveyor: release: $BRANCH and v$v could not be pushed (did $REMOTE/$BRANCH move?); the release commits and the tag are undone, nothing released" >&2; return 1; }
  # Pushed, the release is out: the record says it went over the failed suite, or passed over named commits, and who said so.
  [ ${#passed[@]} = 0 ] || relrec --arg by "$RELBY" --argjson c "$(printf '%s\n' "${passed[@]}" | jq -Rn '[inputs]')" '.allowed = {by: $by, commits: $c}'
  # Its GitHub release's body is the notes, then the known failures, in a scratch file outside the cards folder (gh_write
  # writes that folder's path as <cards>).
  if [ -n "$red" ]; then
    relrec --arg by "$RELBY" '.anyway = (.red + {by: $by})'
    body=$(mktemp) && { cat "$notes" && printf '%s\n' "$known"; } > "$body" \
      || { rm -f "$body"; echo "conveyor: release: v$v is pushed, but its GitHub release's body could not be written: make it from the tag with $notes and a Known test failures section as its body" >&2; return 1; }
  fi
  gh_write release create "v$v" --verify-tag --title "$v" --notes-file "${body:-$notes}" < /dev/null; rc=$?
  [ -z "$body" ] || rm -f "$body"
  [ $rc = 0 ] || { echo "conveyor: release: v$v is pushed, but its GitHub release could not be made: make it from the tag with $notes$([ -z "$red" ] || echo " and a Known test failures section") as its body" >&2; return 1; }
  echo "conveyor: release: v$v is released at ${t:0:12}${red:+, over a failed suite by $RELBY}"
}
# The Board's Release: release-prep, then on its pass release, in the background (above). Without prep, when the
# record (the newest run) is a passed release-prep of <version> on main's head, main not moved since: release alone,
# told that commit. With anyway (Release anyway): release --anyway --by <who> alone, which checks the failed suite.
releasego() { # <version> [prep: release-prep alone | anyway <who>]
  local ok=''
  ( flock -n 9 ) 9>>"$CARDS/release/lock" || { echo "conveyor: release-run: release-prep or release is already running; this one is not started" >&2; return 2; }
  [ -n "${2:-}" ] || { ok=$(jq -er --arg v "$1" 'select(.step == "release-prep" and .state == "passed" and .version == $v and .moved == false) | .sha | strings' "$RELRUN" 2>/dev/null) \
    && [ "$ok" = "$(git rev-parse -q --verify "refs/heads/$BRANCH^{commit}" 2>/dev/null)" ] || ok=''; }
  ( trap '' HUP; exec {LOGFD}>&- && exec {LOGFD}>&2
    export CONVEYOR_RELEASE_PID=$BASHPID
    # release is told the commit release-prep's suite passed on, so a main that moved meanwhile is refused, never run
    # and released again without the owner's second press.
    if [ "${2:-}" = anyway ]; then bash "$HERE/conveyor.sh" release "$1" --anyway --by "$3"
    elif [ -n "$ok" ]; then CONVEYOR_RELEASE_SHA=$ok bash "$HERE/conveyor.sh" release "$1"
    else bash "$HERE/conveyor.sh" release-prep "$1" && [ "${2:-}" != prep ] && CONVEYOR_RELEASE_SHA=$(jq -r '.sha // ""' "$RELRUN") bash "$HERE/conveyor.sh" release "$1"; fi ) >"$CARDS/release/run.log" 2>&1 < /dev/null 8>&- &
  if [ "${2:-}" = prep ]; then echo "conveyor: release-run: release-prep $1 is running, and nothing is released; its output is in $CARDS/release/run.log"
  elif [ "${2:-}" = anyway ]; then echo "conveyor: release-run: release $1 is running over release-prep's failed suite, by $3; its output is in $CARDS/release/run.log"
  elif [ -n "$ok" ]; then echo "conveyor: release-run: release $1 is running, with the suite that passed on ${ok:0:12}; its output is in $CARDS/release/run.log"
  else echo "conveyor: release-run: release-prep $1 is running, then release $1 once its suite passes; their output is in $CARDS/release/run.log"; fi
}
# The run under way ended: its record's pid and every process of the run (relreap()). Only a pid that runs
# conveyor.sh is taken, so a record left by a run that died names no other process. A process of the run relreap cannot
# see still holds the release lock as it ends: the run's release-prep, whose bash carries no mark ps can read (export
# changes no process's own environment) and which leaves the tree of the record's pid once that pid has ended, ends
# on the TERM through its EXIT trap. The stop waits for the lock, so a release-prep started next is not refused. It
# writes the record only holding the lock (the run's own end and the next run write it holding it too), and only while
# the record is still the stopped run's (its pid and start): a run started once the lock was free has its own record,
# which is never marked stopped.
# 1: the lock is still held 10 s on (relreap's time for a TERM; with the stop's own reap, within the Board's 30 s); the
# record is left as it is, and the snapshot shows the run stopped once the lock is free.
releasestop() {
  local p s v lk rc=1
  p=$(jq -er 'select(.ended == null) | .pid | numbers' "$RELRUN" 2>/dev/null) && kill -0 "$p" 2>/dev/null && ps -o args= -p "$p" 2>/dev/null | grep -q 'conveyor\.sh' \
    || { echo "conveyor: release-run stop: no release run is under way; nothing stopped" >&2; return 2; }
  s=$(jq -r '.since' "$RELRUN") && v=$(jq -r '.version' "$RELRUN") || { echo "conveyor: release-run stop: $RELRUN could not be read; nothing stopped" >&2; return 1; }
  relreap "$p" "$p"
  { exec {lk}>>"$CARDS/release/lock"; } 2>/dev/null && flock -w 10 "$lk" && rc=0
  [ $rc != 0 ] || relrec --argjson p "$p" --arg s "$s" --arg t "$(clock)" 'if .pid == $p and .since == $s then .state = "stopped" | .ended = $t | .reasons = ["stopped by the owner"] else . end'
  [ -z "$lk" ] || exec {lk}>&-
  # Not the lock, but another run's record: that run took the lock once this one's processes had let it go.
  [ $rc = 0 ] || jq -e --argjson p "$p" --arg s "$s" '.pid != $p or .since != $s' "$RELRUN" > /dev/null 2>&1 \
    || { echo "conveyor: release-run stop: the run is stopped, but a process of it still holds $CARDS/release/lock; release-prep and release are refused until it ends" >&2; return 1; }
  echo "conveyor: release-run: the release run of $v is stopped"
}
shift
if [ "$CMD_ARG" = release ]; then
  RELUSE='usage: conveyor.sh release <version: X.Y.Z> [--anyway] [--allow-commit <sha>]... [--by <who>: with --anyway or --allow-commit]'
  [ "${1:-}" != --help ] || { echo "$RELUSE"; echo "$RELHELP"; exit 0; }
  # --anyway: the owner's release over release-prep's failed suite; --allow-commit <sha> (any number): a pushed commit
  # whose privacy hits the owner passes over. Either needs --by <who>, a name of one line, and --by needs one of them.
  ver=${1:-}; shift
  while [ $# -gt 0 ]; do
    if [ "$1" = --anyway ]; then RELANY=1; shift
    elif [ $# -ge 2 ] && [ "$1" = --allow-commit ] && [[ $2 =~ ^[0-9a-f]{7,40}$ ]]; then RELALLOW+=("$2"); shift 2
    elif [ $# -ge 2 ] && [ "$1" = --by ] && [[ $2 == *[![:space:]]* && $2 != *$'\n'* ]]; then RELBY=$2; shift 2
    else break; fi
  done
  [ $# = 0 ] && { [ -n "$RELBY" ] && [ -n "$RELANY${RELALLOW[*]}" ] || [ -z "$RELBY$RELANY${RELALLOW[*]}" ]; } \
    && [[ $ver =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] || { printf '%s\n%s\n' "$RELUSE" "$RELHELP" >&2; exit 2; }
  relrun release "$ver"
elif [ "$CMD_ARG" = release-run ]; then
  if [ "$*" = stop ]; then releasestop
  else
    how=; by=
    if [ $# = 2 ] && [ "$1" = prep ]; then how=prep; shift
    elif [ $# = 4 ] && [ "$1" = anyway ] && [ "$3" = --by ] && [[ $4 == *[![:space:]]* && $4 != *$'\n'* ]]; then how=anyway by=$4; set -- "$2"; fi
    [ $# = 1 ] && [[ $1 =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] || { echo "usage: conveyor.sh release-run [prep] <version: X.Y.Z> | release-run anyway <version: X.Y.Z> --by <who> | release-run stop" >&2; exit 2; }
    mkdir -p "$CARDS/release" && releasego "$1" $how "$by"
  fi
else
  [ $# = 1 ] && [[ $1 =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] || { echo "usage: conveyor.sh release-prep <version: X.Y.Z>" >&2; exit 2; }
  relrun releaseprep "$1"
fi
