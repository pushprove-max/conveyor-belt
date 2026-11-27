#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# test-changed.sh's input record (issue 1619): in the loop's test step (CONVEYOR_TEST_LOG) a test file it runs whole runs
# under strace, and when it passes, its log names the tracked files of the checkout that it read, the folders it
# opened and the paths here it looked for and did not find (`TESTRUN inputs`). The engine keeps those with the pass, uses the pass again while they are the same, and
# picks the file for a change to one of them (conveyor/tests/testcache.test.sh). Bugs it catches: the runner named no
# inputs, so no pass was kept or used again and no test was picked by what it read; a file read with no open (a
# readlink of a link, an access check, an exec, a stat after a chdir) not named; a path a test looked for and did
# not find (Node's lookup of a package.json), also from a call strace split, not named, so adding that file ran no
# test; a failed chdir taken as the folder of later paths; an engine case file run with every
# case that named no inputs; a plugin test file named with the reads of the one plugin test run of all of them; a file
# opened for writing alone, a folder only checked, a path outside the checkout or under .git, or the test file itself
# named as an input; and a trace with a path strace escaped (one no tracked path can match), one that read the
# checkout's Git index or objects (the tracked files listed through Git), or one that read a path here that is not
# tracked and was there (a dependency in node_modules, linked from main), named in part, so a change to that file, a
# file added, or a dependency file deleted, would not run the test; and a test that lists the tracked paths alone
# (`git ls-files -z`, as spdx.test.sh does) named no inputs, so nothing selected it for a file added.
set -u
HERE=$(cd "$(dirname "$0")" && pwd -P)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
AT=@
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t${AT}example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t${AT}example.com
unset CONVEYOR_TEST_LOG CONVEYOR_SHELL_TEST_CASE CONVEYOR_TEST_FILE CONVEYOR_TEST_FILELIST BASH_ENV CONVEYOR_TEST_RERUN CONVEYOR_TEST_SLOT CONVEYOR_TEST_SLOTS CONVEYOR_TEST_POOL
fails=0
no() { echo "not ok - $1"; fails=1; }

# A scratch repo: the real script, a map of one area (conveyor/read.sh, conveyor/unread.sh, conveyor/lib/x.sh and
# a.test.sh's one case), the engine's runner (which passes), b.test.sh, a second engine case file (with a.test.sh alone,
# its cases would be every engine case, and the whole-only runner would take that run, as a whole engine run), the
# hooks test hooks/r.test.sh, which reads conveyor/read.sh, lists conveyor/lib/, reads the link link.md (to
# conveyor/read.sh) and checks that tools/run.sh can run, hooks/l.test.sh, which lists the tracked files as
# spdx.test.sh does (git -C <a folder of a name longer than strace prints whole> ls-files -z), the plugin test file
# hooks/u.test.ts, and tools/exec.sh and tools/stat.sh.
R=$T/r; mkdir -p "$R/.conveyor" "$R/conveyor/tests" "$R/conveyor/lib" "$R/hooks" "$R/tools" "$T/bin"
echo 'git -C "$PWD/hooks/../tools/../conveyor/lib/../.." ls-files -z > /dev/null' > "$R/hooks/l.test.sh"
cp "$HERE/test-changed.sh" "$HERE/test-share.sh" "$HERE/lint-shell.sh" "$HERE/test-lint.sh" "$HERE/no-browser-tests.sh" "$HERE/no-records-split.sh" "$R/.conveyor/"
printf '%s\n' '{"area": "a", "file": "conveyor/read.sh"}' '{"area": "a", "file": "conveyor/unread.sh"}' \
  '{"area": "a", "file": "conveyor/lib/x.sh"}' '{"area": "a", "test": "a.test.sh"}' '{"area": "b", "test": "b.test.sh"}' > "$R/.conveyor/engine-areas.json"
printf 't_aone() {\n  :\n}\n' > "$R/conveyor/tests/a.test.sh"; printf 't_bone() {\n  :\n}\n' > "$R/conveyor/tests/b.test.sh"
echo 'exit 0' > "$R/conveyor/conveyor.test.sh"
printf '%s\n' 'cat conveyor/read.sh > /dev/null' 'ls conveyor/lib > /dev/null' 'readlink link.md > /dev/null' '[ -x tools/run.sh ]' > "$R/hooks/r.test.sh"
echo one > "$R/conveyor/read.sh"; echo one > "$R/conveyor/unread.sh"; echo one > "$R/conveyor/lib/x.sh"; ln -s conveyor/read.sh "$R/link.md"
echo one > "$R/tools/run.sh"; chmod +x "$R/tools/run.sh"; echo one > "$R/tools/exec.sh"; echo one > "$R/tools/stat.sh"; echo 'test("u", () => {});' > "$R/hooks/u.test.ts"
echo '{"test": {"files": {"conveyor/conveyor.test.sh": {"wholeOnly": true}}}}' > "$R/.conveyor/project.json"
git -C "$R" init -q && git -C "$R" add -A && git -C "$R" commit -qm init
# stub: strace in the scratch PATH, so the trace the runner reads is the same on every host (one with no strace, or
# where this file itself runs traced, as a card's test step runs it, and a traced process cannot trace). The runner's
# own check (-o /dev/null true) passes with no output; any other call writes $TRACEFIX, <root> made the checkout's
# path, to its -o file and runs the command.
cat > "$T/bin/strace" <<'EOF'
#!/usr/bin/env bash
o=
while [ $# -gt 0 ]; do case $1 in -o|-e) [ "$1" != -o ] || o=$2; shift 2 ;; -*) shift ;; *) break ;; esac; done
[ "$o" != /dev/null ] || exit 0
sed "s#<root>#$(pwd -P)#g" "$TRACEFIX" > "$o"
exec "$@"
EOF
chmod +x "$T/bin/strace"
# claude in the scratch PATH, for the plugin test run (`claude plugin test .`) the runner starts for hooks/u.test.ts:
# it prints the file's heading and a passed case.
# stub: the shared stubs are the engine cases' ($STUB, conveyor/tests/stubs/), and no host has the plugin runner here
printf '%s\n' '#!/usr/bin/env bash' 'printf "hooks/u.test.ts:\n(pass) u\n"' > "$T/bin/claude"
chmod +x "$T/bin/claude"
# run <name> [<trace fixture>] [<test file>]: the one-file mode on the test file (hooks/r.test.sh when none is given) in
# a test step, with the strace stub when given a trace; prints its log's inputs line, the file's name and its inputs.
# It runs the runner on one test file, as the record is made there: the strace probe, the wrapping of the file's
# command and inputsof are parts of the script that cannot be called alone, and only a run of a test file through
# them writes the line the engine reads.
run() {
  mkdir -p "$T/$1"
  (cd "$R" && env ${2:+PATH="$T/bin:$PATH" TRACEFIX="$2"} CONVEYOR_TEST_LOG="$T/$1" bash .conveyor/test-changed.sh --file "${3:-hooks/r.test.sh}") > "$T/$1.out" 2>&1
  echo $? > "$T/$1.rc"
  sed -n 's/^TESTRUN inputs\t//p' "$T/$1/test-changed.log" 2>/dev/null | tr '\t' ' '
}

# The trace names: a read of conveyor/read.sh; conveyor/unread.sh opened to write alone; conveyor/lib opened as a
# folder; conveyor/lib/x.sh from a call strace split (its flags on a line before); the test file itself; .git/HEAD;
# a path outside the checkout; a path in a folder whose name starts with the checkout's; a readlink of link.md (no
# folder given: of the checkout); an access check of tools/run.sh; tools/ only checked, not opened; an exec of
# tools/exec.sh; a failed lookup of hooks/package.json, and one of tools/gone.json from a call strace split; and a stat
# of stat.sh after a chdir to tools/ and a failed chdir to nope/.
cat > "$T/trace" <<'EOF'
100 openat(AT_FDCWD<<root>>, "conveyor/read.sh", O_RDONLY) = 3<<root>/conveyor/read.sh>
100 openat(AT_FDCWD<<root>>, "conveyor/unread.sh", O_WRONLY|O_CREAT|O_TRUNC, 0666) = 3<<root>/conveyor/unread.sh>
100 openat(AT_FDCWD<<root>>, "conveyor/lib", O_RDONLY|O_NONBLOCK|O_CLOEXEC|O_DIRECTORY) = 3<<root>/conveyor/lib>
101 <... openat resumed>) = 4<<root>/conveyor/lib/x.sh>
100 openat(AT_FDCWD<<root>>, "hooks/r.test.sh", O_RDONLY) = 3<<root>/hooks/r.test.sh>
100 openat(AT_FDCWD<<root>>, ".git/HEAD", O_RDONLY) = 3<<root>/.git/HEAD>
100 openat(AT_FDCWD<<root>>, "/etc/hostname", O_RDONLY) = 3</etc/hostname>
100 openat(AT_FDCWD<<root>>, "../rx/conveyor/read.sh", O_RDONLY) = 3<<root>x/conveyor/read.sh>
102 readlink("link.md", "conveyor/read.sh", 4096) = 16
100 faccessat2(AT_FDCWD<<root>>, "tools/run.sh", X_OK, AT_EACCESS) = 0
100 newfstatat(AT_FDCWD<<root>>, "tools", {st_mode=S_IFDIR|0755, st_size=60, ...}, 0) = 0
103 execve("./tools/exec.sh", ["./tools/exec.sh"], 0x7ffd0000 /* 20 vars */) = 0
100 newfstatat(AT_FDCWD<<root>>, "hooks/package.json", 0x7ffd0000, 0) = -1 ENOENT (No such file or directory)
105 statx(AT_FDCWD<<root>>, "tools/gone.json", AT_STATX_SYNC_AS_STAT, STATX_ALL <unfinished ...>
105 <... statx resumed>0x7ffd0000) = -1 ENOENT (No such file or directory)
104 chdir("<root>/tools") = 0
104 chdir("<root>/nope") = -1 ENOENT (No such file or directory)
104 stat("stat.sh", {st_mode=S_IFREG|0644, st_size=4, ...}) = 0
EOF
got=$(run stub "$T/trace")
[ "$got" = "hooks/r.test.sh conveyor/lib/ conveyor/lib/x.sh conveyor/read.sh hooks/package.json link.md nope tools/exec.sh tools/gone.json tools/run.sh tools/stat.sh" ] && [ "$(cat "$T/stub.rc")" = 0 ] \
  || no "given the trace $T/trace, hooks/r.test.sh's inputs line is not its tracked reads, conveyor/lib/ and the paths it did not find: '$got', exit $(cat "$T/stub.rc"): $(cat "$T/stub.out")"

# An engine case file run with every case it holds names what its run read. Bug it catches: only a file run one at a
# time was traced, so it named no inputs. A plugin test file passes and names none: the one plugin test run runs every
# plugin test file, so its reads are not this file's. Bug it catches: each plugin test file named the reads of all of
# them, so a change to one plugin test file ran the plugin test run once for each.
echo '200 openat(AT_FDCWD<<root>>, "conveyor/read.sh", O_RDONLY) = 3<<root>/conveyor/read.sh>' > "$T/trace3"
run engine "$T/trace3" conveyor/tests/a.test.sh > "$T/engine.got"; run plugin "$T/trace3" hooks/u.test.ts > "$T/plugin.got"
[ "$(cat "$T/engine.got")" = "conveyor/tests/a.test.sh conveyor/read.sh" ] && [ "$(cat "$T/engine.rc")" = 0 ] \
  || no "given the trace $T/trace3, the engine case file conveyor/tests/a.test.sh did not name conveyor/read.sh: '$(cat "$T/engine.got")', exit $(cat "$T/engine.rc"): $(cat "$T/engine.out")"
[ ! -s "$T/plugin.got" ] && [ "$(cat "$T/plugin.rc")" = 0 ] && grep -qxF -- '-- ok hooks/u.test.ts' "$T/plugin/test-changed.log" \
  || no "given the trace $T/trace3, the plugin test file hooks/u.test.ts named inputs or did not pass: '$(cat "$T/plugin.got")', exit $(cat "$T/plugin.rc"): $(cat "$T/plugin.out")"

# A trace that opens the checkout's Git index (git ls-files, git diff --cached) or one of its Git objects (git show):
# no inputs line, and the file still passes. Bug it catches: a test that lists the tracked files through Git (an
# SPDX check of each tracked shell file) kept its pass when a file was added, as its inputs named no folder.
for x in index objects/pack/pack-1.idx; do
  { cat "$T/trace"; echo "100 openat(AT_FDCWD<<root>>, \".git/$x\", O_RDONLY|O_CLOEXEC) = 3<<root>/.git/$x>"; } > "$T/trace.${x%%/*}"
  got=$(run "git${x%%/*}" "$T/trace.${x%%/*}")
  [ -z "$got" ] && [ "$(cat "$T/git${x%%/*}.rc")" = 0 ] && grep -qxF -- '-- ok hooks/r.test.sh' "$T/git${x%%/*}/test-changed.log" \
    || no "given the trace $T/trace.${x%%/*}, which opens .git/$x, the run named inputs or did not pass: '$got', exit $(cat "$T/git${x%%/*}.rc"): $(cat "$T/git${x%%/*}.out")"
done

# A process that opens the index after its exec of `git -C <folder> ls-files -z -- <path>` (the folder's name cut short
# by strace) lists the tracked files alone: the inputs name every folder that holds a tracked file too, so a file
# added or deleted anywhere runs the test. Bug it catches: spdx.test.sh, which lists the tracked files so, named no
# inputs, and nothing selected it for a new hooks/new.sh with no SPDX line, which it fails on. Its exec of
# `git ls-files -s` (the staged content of each file, which no input names) still gives no inputs line.
for a in '"-z", "--", "*.sh"' '"-s"'; do
  n=ls${a:2:1}
  { cat "$T/trace"; echo "106 execve(\"/usr/bin/git\", [\"git\", \"-C\", \"<root>/hooks/../tools/../conveyor/\"..., \"ls-files\", $a], 0x7ffd0000 /* 20 vars */) = 0"
    echo '106 openat(AT_FDCWD<<root>>, ".git/index", O_RDONLY|O_CLOEXEC) = 3<<root>/.git/index>'; } > "$T/trace.$n"
  got=$(run "$n" "$T/trace.$n")
  if [ "$n" = lsz ]; then
    want="hooks/r.test.sh $(printf '%s\n' ./ .conveyor/ conveyor/ conveyor/lib/ conveyor/lib/x.sh conveyor/read.sh conveyor/tests/ hooks/ \
      hooks/package.json link.md nope tools/ tools/exec.sh tools/gone.json tools/run.sh tools/stat.sh | LC_ALL=C sort | paste -sd' ')"
  else want=; fi
  [ "$got" = "$want" ] && [ "$(cat "$T/$n.rc")" = 0 ] && grep -qxF -- '-- ok hooks/r.test.sh' "$T/$n/test-changed.log" \
    || no "given the trace $T/trace.$n, an exec of git ls-files $a that opens the index, the inputs line is '$got', not '$want', exit $(cat "$T/$n.rc"): $(cat "$T/$n.out")"
done

# A trace that found node_modules/jsdom, a path here that is not tracked (a dependency folder linked from main), as Node
# does when a test loads jsdom: no inputs line, and the file still passes. Bug it catches: a test that loaded jsdom kept
# its pass after a file of jsdom was deleted, as no input named the files it read there.
{ cat "$T/trace"; echo '100 statx(AT_FDCWD<<root>>, "node_modules/jsdom", AT_STATX_SYNC_AS_STAT, STATX_ALL, {stx_mode=S_IFDIR|0755, ...}) = 0'; } > "$T/trace.deps"
got=$(run deps "$T/trace.deps")
[ -z "$got" ] && [ "$(cat "$T/deps.rc")" = 0 ] && grep -qxF -- '-- ok hooks/r.test.sh' "$T/deps/test-changed.log" \
  || no "given the trace $T/trace.deps, which finds node_modules/jsdom (not tracked), the run named inputs or did not pass: '$got', exit $(cat "$T/deps.rc"): $(cat "$T/deps.out")"

# CONVEYOR_TEST_NOTRACE set (the run before a push, for a file whose list of inputs is fresh): the file runs untraced,
# naming no inputs, and passes. Bug it catches: such a file was traced again, the slow part of the run before a push.
got=$(CONVEYOR_TEST_NOTRACE=1 run notrace "$T/trace")
[ -z "$got" ] && [ "$(cat "$T/notrace.rc")" = 0 ] && grep -qxF -- '-- ok hooks/r.test.sh' "$T/notrace/test-changed.log" \
  || no "given the trace $T/trace and CONVEYOR_TEST_NOTRACE=1, the run named inputs or did not pass: '$got', exit $(cat "$T/notrace.rc"): $(cat "$T/notrace.out")"

# A path here that strace wrote escaped: no inputs line at all, and the file still passes.
{ cat "$T/trace"; echo '100 openat(AT_FDCWD<<root>>, "conveyor/r\303\251ad.sh", O_RDONLY) = 3<<root>/conveyor/r\303\251ad.sh>'; } > "$T/trace2"
got=$(run escaped "$T/trace2")
[ -z "$got" ] && [ "$(cat "$T/escaped.rc")" = 0 ] && grep -qxF -- '-- ok hooks/r.test.sh' "$T/escaped/test-changed.log" \
  || no "given the trace $T/trace2, with an escaped path, the run named inputs or did not pass: '$got', exit $(cat "$T/escaped.rc"): $(cat "$T/escaped.out")"

# With the host's own strace, where it can trace here (not where this file runs traced): the real trace gives the same
# reads, so the runner's strace options and its reading of strace's lines agree.
if command -v strace > /dev/null 2>&1 && [ -z "$(strace -D -f -qq --seccomp-bpf -y -e trace=%file -o /dev/null true 2>&1)" ]; then
  got=$(run real)
  [ "$got" = "hooks/r.test.sh conveyor/lib/ conveyor/read.sh link.md tools/run.sh" ] && [ "$(cat "$T/real.rc")" = 0 ] \
    || no "under the host's strace, hooks/r.test.sh (cat conveyor/read.sh; ls conveyor/lib; readlink link.md; [ -x tools/run.sh ]) did not name its reads as inputs: '$got', exit $(cat "$T/real.rc"): $(cat "$T/real.out")"
  # The real strace cuts the long -C folder short, as the stub's trace above does, and git opens the index itself.
  got=$(run reallist "" hooks/l.test.sh)
  [ "$got" = "hooks/l.test.sh ./ .conveyor/ conveyor/ conveyor/lib/ conveyor/tests/ hooks/ tools/" ] && [ "$(cat "$T/reallist.rc")" = 0 ] \
    || no "under the host's strace, hooks/l.test.sh (git -C <a long folder> ls-files -z) did not name every folder that holds a tracked file: '$got', exit $(cat "$T/reallist.rc"): $(cat "$T/reallist.out")"
else
  echo "# the host's strace cannot trace here: its own case did not run"
fi
[ $fails = 0 ] && echo "ok - test-changed names the files a test file read" || exit 1
