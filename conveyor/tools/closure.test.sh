#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 600
# Release 1 runs from its computed closure alone (plan section 11): closure.sh's set, copied into an empty folder with
# no host project's checkout reachable, runs every release-1 hook's tests, the Board's and the engine's. A file the set
# misses fails here; so does a set that names a file it does not hold, and removing any one file of the set. In quick
# mode (CONVEYOR_CLOSURE_QUICK=1) the tests from the copy are not run: every other check is (t_install).
set -uo pipefail
SRC=$(cd "$(dirname "$0")" && pwd -P); TOP=$(cd "$SRC/../.." && pwd -P)
# This file's own sed -i is a GNU call: on macOS it runs Homebrew's, as the engine's does (portable.sh).
. "$SRC/../lib/portable.sh"; p_tools
. "$SRC/../tests/wait.sh"
# The machine's test slots: each case that runs beside another, and each unit of install and remove, holds one.
# Each command run() starts (a unit's test, a closure of remove's) runs in its slot's box (slot_box): one core and the
# slot's share of the memory, as the loop's test step runs each other test file; it is told it runs in one
# (CONVEYOR_TEST_BOX, through run()'s clean environment), as it is where this runner runs in a box already.
. "$SRC/../lib/slots.sh"; slot_pool || exit 1; slot_box; BOXED=${CONVEYOR_TEST_BOX:-${SLOT_BOX[0]:+1}}
# The install's HOME is a fresh folder, not the user's; it sits under the user's HOME, not under scratch space, which
# hook tests treat apart (bash-guardrails-search's checkout box).
T=$(mktemp -d); H=$(mktemp -d "$HOME/.closure-test.XXXXXX"); trap 'rm -rf "$T" "$H"' EXIT
fail() { echo "FAIL [$CASE]: $*" >&2; exit 1; }
# Quick mode (a card's test step sets it: .conveyor/test-changed.sh): install runs a stub unit in place of its units.
QUICK=${CONVEYOR_CLOSURE_QUICK:-}
SET=$T/set; bash "$SRC/closure.sh" > "$SET" || { echo "FAIL: closure.sh exited non-zero" >&2; exit 1; }
# Bug (issue 563): a shipped file the set misses (one sourced through a path built at run time) failed the cases that
# copy the set only after every test had run from the copy, 20 to 30 minutes. Each such file is listed here in seconds,
# and install() fails on it before it makes the copy.
UNREACHED=$T/unreached; bash "$SRC/closure.sh" --unreached > "$UNREACHED" || { echo "FAIL: closure.sh --unreached exited non-zero" >&2; exit 1; }
# The set's files copied into a folder, with their modes and times, by one tar each way, not a mkdir and a cp a file.
copyset() { mkdir -p "$1" && tar -C "$TOP" -cf - -T "$SET" | tar -C "$1" -xpf -; }

# Bugs: a dependency the plan names (section 11) is left out of the set; product code, or what section 11 keeps in
# the host project (the pack and its hooks, the area rule files, the startup instructions), is pulled into a set that will be
# published.
t_set() {
  local f
  for f in .claude/hooks/lib/edit-payload.sh .claude/hooks/lib/strip-quoted.sh .claude/scripts/decision.sh \
    conveyor/conveyor.sh conveyor/lib/pack.sh conveyor/jq/rows.jq .claude/dashboard/panels/belt.js; do
    grep -qxF "$f" "$SET" || fail "the set misses $f"
  done
  # Bug: the plugin's hooks.json runs a file (the shim, a hook) the install does not hold, so the hook fails there.
  grep -qxF hooks/hooks.json "$SET" || fail "the set misses hooks/hooks.json"
  jq -r '.hooks[][].hooks[].command' "$TOP/hooks/hooks.json" | grep -oE '(\$\{CLAUDE_PLUGIN_ROOT\}"?/)?[^ "]+\.sh' \
    | sed 's|^${CLAUDE_PLUGIN_ROOT}"*/||' | sort -u > "$T/plugin-hooks"
  grep -qxF shim.sh "$T/plugin-hooks" || fail "read no shim.sh from hooks/hooks.json"
  while IFS= read -r f; do grep -qxF "$f" "$SET" || fail "the set misses $f, which hooks/hooks.json runs"; done < "$T/plugin-hooks"
  # Bug (#166): /units (hooks/units.tsx) runs its fetch script by a path built at run time, which the set missed, so
  # the Board's readers failed from the install with "units-fetch.sh: No such file or directory".
  f=$(sed -n "s/^const FETCH = '\([^']*\)'.*/\1/p" "$TOP/hooks/units.tsx"); [ -n "$f" ] || fail "read no fetch script from hooks/units.tsx"
  grep -qxF "$f" "$SET" || fail "the set misses $f, which hooks/units.tsx runs"
  ! grep -E '^(src|web|shared|lambdas|infra|ml)/' "$SET" || fail "the set holds product code"
  # The pack's hooks: a fixture checkout (the set, the test pack's hooks.json as its pack's, each hook it names beside
  # the release-1 hooks), never this repo's .conveyor/, whose pack may name no hooks.
  local d=$T/packhooks.d f
  copyset "$d" || fail "cannot copy the set"
  mkdir -p "$d/.conveyor" && cp "$TOP/conveyor/lib/test-hooks.json" "$d/.conveyor/hooks.json" || fail "cannot copy the test pack's hooks.json"
  sed -n 's|.*"\$CLAUDE_PROJECT_DIR\\*"*/\([^"\\]*\).*|\1|p' "$d/.conveyor/hooks.json" > "$T/packhooks"
  [ "$(wc -l < "$T/packhooks")" -ge 3 ] || fail "read no hooks from the pack's hooks.json"
  while IFS= read -r f; do printf '#!/usr/bin/env bash\nexit 0\n' > "$d/$f" || fail "cannot make $f"; done < "$T/packhooks"
  git -C "$d" init -q && git -C "$d" add -A || fail "cannot make the fixture a repository"
  bash "$SRC/closure.sh" "$d" > "$T/packhooks.set" || fail "the closure of the fixture failed"
  ! grep -xFf "$T/packhooks" "$T/packhooks.set" || fail "the set holds the pack's hooks"
  ! grep -E '^(\.claude/rules/|\.claude/commands/|\.conveyor/|AGENT_STARTUP\.md$|CLAUDE\.md$)' "$SET" || fail "the set holds what stays in the host project"
}

# Bug: a release-1 file that reads a file of the project pack folder (.conveyor/) by a literal path pulls it into the
# set, so the import refuses the whole set.
t_pack() {
  local d=$T/pack
  copyset "$d" || fail "cannot copy the set"
  sed -i '1a HERE=$(dirname "$0"); cat "$HERE/../.conveyor/x" "$(git rev-parse --show-toplevel)/.conveyor/y"' "$d/conveyor/conveyor.sh"
  mkdir -p "$d/.conveyor" && echo x > "$d/.conveyor/x" && echo y > "$d/.conveyor/y"
  git -C "$d" init -q && git -C "$d" add -A || fail "cannot make the fixture a repository"
  bash "$SRC/closure.sh" "$d" > "$T/pack.set" || fail "the closure of the fixture failed"
  grep -qxF conveyor/conveyor.sh "$T/pack.set" || fail "the fixture's closure misses its entry point"
  ! grep '^\.conveyor/' "$T/pack.set" || fail "a read of the project pack is followed"
}

# Bug: a file the code needs is left out of the set because the code first tests for it, though its absence stops the
# code ([ -f x ] || exit 1; . x), as if it were optional.
t_required() {
  local d=$T/req l
  install; mkdir -p "$d" && cp -a "$I/." "$d/" && rm -rf "$d/node_modules" || fail "cannot copy the install"
  for l in '[ -f "$HERE/lib/req1.sh" ] || exit 1; . "$HERE/lib/req1.sh"' \
    '[ -e "$HERE/lib/req2.sh" ] || { echo "no req2" >&2; exit 2; }; . "$HERE/lib/req2.sh"' \
    '[ ! -f "$HERE/lib/req3.sh" ] \&\& exit 1; . "$HERE/lib/req3.sh"' \
    '[ -f "$HERE/lib/opt1.sh" ] || exit 0; . "$HERE/lib/opt1.sh"' '[ ! -e "$HERE/lib/opt2.sh" ] || . "$HERE/lib/opt2.sh"'; do
    sed -i "1a HERE=\$(dirname \"\$0\"); $l" "$d/conveyor/conveyor.sh"
  done
  for l in req1 req2 req3 opt1 opt2; do echo : > "$d/conveyor/lib/$l.sh"; done
  ( cd "$d" && run git add -A && run git commit -qm req ) || fail "cannot commit the fixture"
  (cd "$I" && run bash conveyor/tools/closure.sh "$d") > "$T/req.set" || fail "the closure of the fixture failed"
  for l in req1 req2 req3; do grep -qxF "conveyor/lib/$l.sh" "$T/req.set" || fail "a file whose absence stops the code ($l) is left out"; done
  ! grep -E 'conveyor/lib/opt[12]\.sh' "$T/req.set" || fail "an optional file is in the set"
}

# The install: the set copied into an empty folder, made a repository of its own. run() runs a command in it with the
# checkout out of reach: every worktree of the checkout's repository is an empty folder (bwrap; on macOS, which has no
# bwrap, sandbox-exec denies reading or writing it), its own PID namespace
# leaves no host process's /proc/<pid>/root to reach the host's filesystem through, no variable of its
# environment comes along (CONVEYOR_*, GIT_*, CLAUDE_PROJECT_DIR), none of its folders is on PATH and HOME is a fresh
# folder holding only a git identity and the machine's test slots (a host file of the pool's size and folder alone: a
# runner in the install that read none would take the pool for the machine's cores, past a smaller testSlots), so no
# other host configuration is read. The one variable that comes along is
# CONVEYOR_TEST_SLOT, the test slot the command runs on (a runner in it must not take a second). The npm packages two tests load (jsdom for the Board's page, typescript for new-test-file-guard) are
# dependencies, not the checkout: their node_modules is mounted read-only as the install's own. Each case that needs
# an install builds its own (install writes to it).
printf '[user]\n\tname = t\n\temail = t@users.noreply.github.com\n' > "$H/.gitconfig"
mkdir -p "$H/.config/conveyor" && jq -n --argjson n "$SLOT_N" --arg d "$SLOT_DIR" '{testSlots: $n, testSlotsDir: $d}' > "$H/.config/conveyor/host.json" \
  || { echo "the install's host file, of the machine's test slots, cannot be written" >&2; exit 1; }
# As many units at once as there are test slots on the machine (lib/slots.sh): each unit waits for a slot of its own
# before it starts (the run's home slot, or one of the pool) and holds it, on the slot's core, with all it runs, which
# inherit the descriptor: the slot comes back when the last of them has ended (held), so the units of every run on the
# machine together never pass the pool.
J=$SLOT_N; export SLOT_DIR SLOT_N SLOT_CPUS SLOT_HOME SLOT_HOME_K SLOT_TURN; export -f slot_try slot_wait slot_yield slot_take slot_mine
install() {
  local f p w nm bv hide=()
  [ ! -s "$UNREACHED" ] || fail "$(sed 's/$/: closure.sh does not reach it: add an anchored source, or a line to the left-out list/' "$UNREACHED")"
  [ "$(uname -s)" = Darwin ] || command -v bwrap >/dev/null || fail "bwrap is not installed: the install cannot run with the checkout out of reach"
  I=$T/install.$CASE; rm -rf "$I"; mkdir -p "$T/tmp" "$T/out"
  copyset "$I" || fail "cannot copy the set"
  path=''; IFS=: read -ra p <<<"$PATH"; for f in "${p[@]}"; do case $f/ in "$TOP"/*) ;; *) path=${path:+$path:}$f ;; esac; done
  # A checkout with no node_modules (a project with no npm dependencies) mounts none.
  nm=$(readlink -f "$TOP/node_modules") && [ -d "$nm" ] || nm=''
  # The Board's virtualenv (setup fills it; the Board's tests run on it) is a dependency too: mounted read-only where the
  # install's fresh HOME looks for it. A machine with none mounts none, and the Board's tests say to run setup.
  bv=$(readlink -f "${XDG_DATA_HOME:-$HOME/.local/share}/conveyor/board-venv") && [ -d "$bv" ] || bv=''
  [ -z "$bv" ] || mkdir -p "$H/.local/share/conveyor" || fail "cannot make the install's data folder"
  if [ "$(uname -s)" = Darwin ]; then
    # The last rule that matches wins: the worktrees are denied, then node_modules (which may sit in one, or anywhere
    # else) allowed back to read, never to write, through a link in its place. macOS has no /proc, so no process's root
    # reaches the host's filesystem.
    local sb='(version 1)(allow default)'
    while IFS= read -r w; do sb+="(deny file-read* file-write* (subpath \"${w#worktree }\"))"; done < <(git -C "$TOP" worktree list --porcelain | grep '^worktree ')
    [ -z "$nm" ] || { sb+="(allow file-read* (subpath \"$nm\"))(deny file-write* (subpath \"$nm\"))"; ln -s "$nm" "$I/node_modules"; }
    [ -z "$bv" ] || { sb+="(allow file-read* (subpath \"$bv\"))(deny file-write* (subpath \"$bv\"))"; ln -sfn "$bv" "$H/.local/share/conveyor/board-venv"; }
    BW=(sandbox-exec -p "$sb")
  else
    while IFS= read -r w; do hide+=(--tmpfs "${w#worktree }"); done < <(git -C "$TOP" worktree list --porcelain | grep '^worktree ')
    # /tmp is the run's own: in a PID namespace every run's tests have the same process ids, so two runs at once on
    # one machine (two cards) would share each /tmp file a hook test names by its id, and fail each other. The test
    # slots stay the machine's: a pool of the run's own would let its workers past the machine's limit.
    BW=(bwrap --die-with-parent --unshare-pid --bind / / --dev /dev --proc /proc "${hide[@]}" --bind "$T/tmp" /tmp --bind "$T" "$T" --bind "$SLOT_DIR" "$SLOT_DIR")
    [ -z "$nm" ] || { mkdir "$I/node_modules"; BW+=(--ro-bind "$nm" "$I/node_modules"); }
    [ -z "$bv" ] || { mkdir -p "$H/.local/share/conveyor/board-venv"; BW+=(--ro-bind "$bv" "$H/.local/share/conveyor/board-venv"); }
  fi
  ( cd "$I" && run git init -q && run git add -A -- . ':!node_modules' \
    && run git commit -qm release-1 ) || fail "cannot make the install a repository"
  # A runner in the install takes its workers' slots from the machine's pool at its size, not at the cores'.
  [ "$( cd "$I" && run bash -c '. conveyor/lib/slots.sh; slot_pool; echo "$SLOT_N $SLOT_DIR"' )" = "$SLOT_N $SLOT_DIR" ] \
    || fail "the install's runs do not see the machine's test slots ($SLOT_N in $SLOT_DIR)"
  # The same files, not a folder of that name of the install's own: a lock on another file holds no slot of the machine's.
  ( cd "$I" && run bash -c '[ /dev/fd/9 -ef "$1/1" ]' _ "$SLOT_DIR" ) 9< "$SLOT_DIR/1" \
    || fail "the install's test slots are not the machine's files: its runs would take slots no other run sees"
  ( cd "$I" && run test ! -e "$TOP/conveyor/conveyor.sh" ) || fail "the checkout is reachable from the install's runs"
  ( cd "$I" && run bash -c 'for p in "/proc/$1" /proc/[0-9]*; do [ ! -e "$p/root$2" ] || exit 1; done' _ "$$" "$TOP/conveyor/conveyor.sh" ) \
    || fail "the checkout is reachable from the install's runs through a process's root"
  # A test that starts an operating-system sandbox of its own (the research lane's, research-bash; the quick-mode cases,
  # closurequick and closuremiss, which run this tool and so its install's sandbox) can start it inside
  # this one only where the host lets a sandboxed process start another. Ubuntu's AppArmor (bwrap-userns-restrict)
  # does not: what bwrap starts runs as unpriv_bwrap, which is denied every capability, so a bwrap started there cannot
  # make its namespaces (and each try logs a denial; the label is read instead). There that test runs with the rest of
  # run()'s isolation (a clean environment, HOME and PATH), out of this sandbox.
  NEST=1
  if [ "$(uname -s)" = Darwin ]; then ( cd "$I" && run sandbox-exec -p '(version 1)(allow default)' true ) >/dev/null 2>&1 || NEST=
  else ! ( cd "$I" && run grep -qs unpriv_bwrap /proc/self/attr/apparmor/current ) || NEST=; fi
  # A unit's command runs in its slot's box, where one can be made, and knows it does.
  [ ${#SLOT_BOX[@]} = 0 ] || ( cd "$I" && run bash -c '[ "$CONVEYOR_TEST_BOX" = 1 ] && grep -qx "100000 100000" "/sys/fs/cgroup$(cut -d: -f3 /proc/self/cgroup)/cpu.max"' ) \
    || fail "the install's runs are not in their test slot's box (one core): a unit could take the machine from every other card"
  export path T H I BW_DECL NEST BOXED; BW_DECL=$(declare -p BW SLOT_BOX)
  export -f run
}
# RUN set (held): the command is started by it, the words before the command's own. The box (SLOT_BOX) is outside
# the sandbox and its clean environment, which leave systemd-run no user manager to reach.
run() { "${RUN[@]}" "${SLOT_BOX[@]}" "${BW[@]}" env -i HOME="$H" PATH="$path" TMPDIR="$T/tmp" LANG=C.UTF-8 USER="${USER:-t}" ${BOXED:+CONVEYOR_TEST_BOX=1} ${CONVEYOR_TEST_SLOT:+CONVEYOR_TEST_SLOT=$CONVEYOR_TEST_SLOT} ${U_CASE:+CONVEYOR_SHELL_TEST_CASE=$U_CASE} "$@"; }
# The holder of a unit: <the descriptors that hold the unit's slot, comma-separated> <the unit's mark> <command...>.
# It starts the command with those descriptors alone, writes the command's exit status to descriptor 3 once it has
# ended, then holds the slot, and no other descriptor it was given, until no process the command started is left. What
# tells it one is left is nothing such a process can drop (its environment), close (a descriptor) or leave (its process
# group, its session):
# - Linux: the holder is the reaper of every process below it (PR_SET_CHILD_SUBREAPER, 36), so each one whose parent
#   has ended is its child, and it waits for the last of its children.
# - macOS, a unit in the sandbox: the unit's sandbox, which every process started in it keeps for life, alone refuses
#   the Mach name that is the unit's mark and allows the name beside it (a sandbox of another program that refuses all
#   names refuses both); sandbox_check asks that of each of the user's processes. The list of them is the kernel's own,
#   taken at one instant (proc_listpids, under its lock on the list; ps resolves each process after the kernel has
#   listed it, and shows neither one that ended in between nor what that one started): every process of the unit that
#   runs at that instant is in it, and each one started later comes of one of them. One of them that ends between the
#   list and the question may have started another, in no list yet, before it ended, and the answer is then an ended
#   process's, or that of an unmarked process started since at the same pid. So an answer counts only for a process
#   that had not ended just before and just after the question, was the same at both (its start, to the microsecond)
#   and started before the list was taken; a listed process that has ended (waited for or not) counts only when the
#   round before saw it ended, the same one, so it had started its last before this list; else a process may be left,
#   and the holder asks again at once.
# - macOS, a unit out of the sandbox: the command's process group (timeout makes one of it) is all that tells: macOS
#   gives no more for a process in no sandbox.
HOLD='import ctypes, os, struct, subprocess, sys, time
keep = [int(f) for f in sys.argv[1].split(",")]
mark = sys.argv[2].encode()
c = ctypes.CDLL(None)
linux = sys.platform == "linux"
if linux and c.prctl(36, 1, 0, 0, 0):
    sys.exit("the holder of a unit cannot be made the reaper of its processes: the unit does not start")
p = subprocess.Popen(sys.argv[3:], pass_fds=keep)
rc = p.wait()
os.write(3, b"%d" % (rc if rc >= 0 else 128 - rc))
os.dup2(os.open(os.devnull, os.O_RDWR), 0); os.dup2(0, 1); os.dup2(0, 2)
for f in range(3, 256):
    if f not in keep:
        try: os.close(f)
        except OSError: pass
if linux:
    try:
        while True: os.wait()
    except ChildProcessError: pass
else:
    chk = c.sandbox_check; chk.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_int]
    name = 2 | ctypes.c_int.in_dll(c, "SANDBOX_CHECK_NO_REPORT").value # SANDBOX_FILTER_GLOBAL_NAME, unlogged
    def refused(pid, n): return chk(pid, b"mach-lookup", name, ctypes.c_char_p(n))
    lst = c.proc_listpids; lst.argtypes = [ctypes.c_uint32, ctypes.c_uint32, ctypes.c_void_p, ctypes.c_int]
    info = c.proc_pidinfo; info.argtypes = [ctypes.c_int, ctypes.c_int, ctypes.c_uint64, ctypes.c_void_p, ctypes.c_int]
    ids = (ctypes.c_int * 100000)() # room for every pid there is (the last is 99999): the list is never cut short
    b = ctypes.create_string_buffer(136) # struct proc_bsdinfo: pbi_status at 4, pbi_start_tvsec and _tvusec at 120
    def seen(pid): # the process at the pid: (ended and not yet waited for, its start in us); None when none is there
        if info(pid, 3, 1, b, 136) != 136: return None # 3: PROC_PIDTBSDINFO; 1: of an ended process too
        s, us = struct.unpack_from("QQ", b, 120)
        return struct.unpack_from("I", b, 4)[0] == 5, s * 1000000 + us # 5: SZOMB
    ended = set() # the processes the last round saw ended and not yet waited for: (pid, start)
    def left(): # True: a process of the unit is left; None: one may be; False: none is
        global ended
        try: os.killpg(p.pid, 0); return True
        except OSError: pass
        was, ended, none = ended, set(), False
        t = time.time_ns() // 1000
        n = lst(4, os.geteuid(), ids, ctypes.sizeof(ids)) // 4 # 4: PROC_UID_ONLY; the holder itself is one
        if n < 1: return None
        for i in ids[:n]:
            a = seen(i)
            if a and a[0]:
                ended.add((i, a[1]))
                if (i, a[1]) not in was: none = None
                continue
            if refused(i, mark) == 1 and refused(i, mark + b".free") == 0: return True
            if a is None or a != seen(i) or a[1] >= t: none = None # not the listed process, for all that tells
        return none
    while True:
        l = left()
        if l is False: break
        if l: time.sleep(0.5)'
# A unit's command, run from the current folder under the unit's 600 s, by a worker that holds the unit's slot. A
# process left of it may have closed the descriptor that holds the slot (a program that closes all it inherits before
# it starts another): the unit's holder (HOLD), which the worker waits on only for the command's exit status, holds the
# slot until the last of them has ended. For a unit on the run's home slot that is the turn and the home slot's own
# descriptor, which this run's end would else close: the machine's slot would go to another run with the process still
# on its core.
held() { # <command...>
  local rc k=$SLOT_FD u=conveyor.unit.$BASHPID.$RANDOM BW=("${BW[@]}")
  [ "$SLOT_ENV" = "$SLOT_FD" ] || k+=,$SLOT_HOME
  [ "${BW[0]:-}" != sandbox-exec ] || BW[2]+="(deny mach-lookup (global-name \"$u\"))"
  local RUN=(python3 -I -c "$HOLD" "$k" "$u")
  { rc=$(run timeout 600 "$@" 3>&1 >&8 8>&- &); } 8>&1
  return "${rc:-1}"
}
export HOLD; export -f held

# Bugs: closure.sh misses a file a release-1 part reaches (a test green in the checkout fails from the install), or the
# set needs the checkout (a file of it read through the environment or a path outside the set).
t_install() {
  local f c
  install
  # The install's own closure is the set: every file it names is there, and it needs no file beyond.
  [ "$(cd "$I" && run bash conveyor/tools/closure.sh)" = "$(cat "$SET")" ] || fail "the install's closure is not the set: $(diff <(cd "$I" && run bash conveyor/tools/closure.sh) "$SET")"
  ! grep -rlF "$TOP" "$I" --exclude-dir=.git --exclude-dir=node_modules || fail "a file of the set names the checkout"
  # Every test file of the set, but: this one; the two .test.sh wrappers that hand .test.mjs files of the set to the host project's
  # npm runner (each .test.mjs runs here directly); a test the host project quarantines, which no gate runs.
  # The quarantine list is the project's own data, not part of the set: a checkout without one quarantines nothing.
  : > "$T/quarantine"
  [ ! -f "$TOP/.claude/metrics/test-quarantine.tsv" ] || cut -f1 "$TOP/.claude/metrics/test-quarantine.tsv" | grep -v '^#' > "$T/quarantine"
  grep -E '\.test\.(sh|py|mjs)$' "$SET" | grep -vxF -e conveyor/tools/closure.test.sh \
    -e .claude/scripts/__tests__/dashboard-view.test.sh -e .claude/scripts/__tests__/dashboard-collector-incremental.test.sh \
    | grep -vxFf "$T/quarantine" > "$T/tests"
  ! { (cd "$TOP" && ls .claude/scripts/__tests__/dashboard-view.*.test.mjs); echo .claude/scripts/__tests__/dashboard-collector-incremental.test.mjs; } \
    | grep -vxFf "$T/tests" | grep -q . || fail "a wrapped .test.mjs is not run"
  # A unit is a test file, or one case of a file that runs its cases by name (ALL=), so a red case hides no later one.
  # The engine's cases are each a unit of the area file that holds them (conveyor/tests/, its t_<case> functions), not
  # of the runner, conveyor/conveyor.test.sh, which runs the same cases. Not the engine's packrules case: it checks
  # the host project's pack's card rules and hooks (the .conveyor/ folder, never in the set).
  while IFS= read -r f; do
    case $f in
      conveyor/conveyor.test.sh) continue ;;
      conveyor/tests/*) c=$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$I/$f") ;;
      *) c=$(sed -n 's/^ALL="\(.*\)"$/\1/p' "$I/$f") ;;
    esac
    if [ -n "$c" ]; then for c in $c; do echo "$f $c"; done; else echo "$f"; fi
  done < "$T/tests" | grep -vxF -e 'conveyor/tests/rules.test.sh packrules' > "$T/units"
  grep -qxF 'conveyor/tests/rules.test.sh rules' "$T/units" || fail "the engine's rules case is not run"
  unit() { # <test file> [case]
    local f=$1 o=$T/out/${1//\//_}${2:+.$2} c BW=("${BW[@]}"); export U_CASE=${2:-}
    # The research lane's test starts the lane's sandbox, the quick-mode cases this tool's: out of the install's where
    # one cannot start in another (NEST).
    [ -n "$NEST" ] || case $f in conveyor/lanes/research.test.sh | conveyor/tests/closurequick.test.sh | conveyor/tests/closuremiss.test.sh) BW=() ;; esac
    case $f in *.sh) c=(bash "$f") ;; *.py) c=(python3 "$f") ;; *.mjs) c=(node --max-old-space-size=4096 --test "$f") ;; esac
    slot_take; slot_mine # the unit's 600 s and its seconds start with its slot
    local s=$SECONDS
    if (cd "$I" && held "${c[@]}") > "$o" 2>&1; then echo "ok $* ($((SECONDS - s)) s)"; else echo "FAIL $*"; tail -20 "$o"; fi
  }
  export -f unit
  if [ -n "$QUICK" ]; then
    # Quick mode (CONVEYOR_CLOSURE_QUICK=1, a card's test step): every check before and after the units runs, but no
    # unit: the units test the release set, not this tool, and the nightly whole test runs them all. In their place one
    # stub unit starts as each unit does and writes the folder, the test slot and the box it was started in.
    echo "quick: $(wc -l < "$T/units") units from the copy left to the whole test"
    echo 'echo "$(pwd -P) ${CONVEYOR_TEST_SLOT:-} ${CONVEYOR_TEST_BOX:-}" > "$1"' > "$T/stub.sh"
    bash -c 'eval "$BW_DECL"; slot_take; slot_mine; echo "$(cd "$I" && pwd -P) $CONVEYOR_TEST_SLOT $BOXED" > "$T/stub.want"
      cd "$I" && held bash "$T/stub.sh" "$T/stub.seen"' || fail "the stub unit failed"
    [ "$(cat "$T/stub.seen" 2>/dev/null)" = "$(cat "$T/stub.want")" ] \
      || fail "the stub unit did not start in the install, on its test slot, in its box: '$(cat "$T/stub.seen" 2>/dev/null)', not '$(cat "$T/stub.want")'"
    echo "ok stub unit ($(cat "$T/stub.seen"))"
  else
    # The slowest units (closure.slowest, as measured) start first, the rest after, so no long unit starts last.
    sed -n 's/^\([^#].*\) [0-9]*$/\1/p' "$SRC/closure.slowest" | grep -xFf "$T/units" > "$T/order"
    grep -vxFf "$T/order" "$T/units" >> "$T/order"
    xargs -P "$J" -L1 bash -c 'eval "$BW_DECL"; unit "$@"' _ < "$T/order" > "$T/report"
    cat "$T/report"; ! grep -q '^FAIL ' "$T/report" || fail "a test failed from the install"
    [ "$(grep -c '^ok ' "$T/report")" = "$(wc -l < "$T/units")" ] || fail "not every test ran"
  fi
  # bash-write-rules, from the install (which ships no rules), gives a shell write the project's rule for its path; a
  # project with no rules gets nothing and no error.
  local p=$T/project o
  [ ! -e "$I/.claude/rules" ] || fail "the install ships rules of its own"
  mkdir -p "$p/.claude/rules" "$p.bare" && printf -- '---\npaths: ["docs/zz/**"]\n---\nZZ-RULE\n' > "$p/.claude/rules/zz.md"
  bwr() { # <project> -> the hook's output and errors for a shell write into docs/zz there
    ( cd "$1" && jq -cn --arg cwd "$1" '{session_id: "closure-\(now)", cwd: $cwd, tool_input: {command: "echo x > docs/zz/a.md"}}' \
      | run env CLAUDE_PROJECT_DIR="$1" bash "$I/.claude/hooks/bash-write-rules.sh" 2>&1 )
  }
  bwr "$p" | grep -q ZZ-RULE || fail "bash-write-rules from the install did not give the project's rule"
  o=$(bwr "$p.bare") && [ -z "$o" ] || fail "bash-write-rules from the install, for a project with no rules, said: $o"
  rm -f /tmp/claude-bash-rules-zz-closure-*
}

# Bugs: a file of the set can go missing unnoticed. Each file removed in turn from a copy of the install, the copy's
# closure fails and names it (computed by the install's closure.sh, so removing closure.sh itself is named too).
t_remove() {
  install
  # Each worker takes its share of the set on one slot, with one copy of the install and one run(), in which each file
  # of the share is moved out of the copy, the closure run, and the file put back: a copy and a run() a file were most
  # of the case's time.
  gone() { # <file...>
    local d=$T/rm/$BASHPID f
    slot_take; slot_mine
    # A hard-linked copy: closure.sh only reads it, and a file is moved out of the copy alone.
    mkdir -p "$d" && cp -al "$I/." "$d/" && rm -rf "$d/node_modules" || { for f; do echo "FAIL $f: cannot copy"; done; return; }
    # A file not put back would be missing from the next file's closure too: the rest of the share is not run.
    (cd "$I" && run bash -c 'd=$1; shift; for f; do
      mv "$d/$f" "$d.gone" || { echo "FAIL $f: cannot move it out"; exit 1; }
      if bash conveyor/tools/closure.sh "$d" > "$d.out" 2>&1; then echo "FAIL $f: the closure passed without it"
      elif grep -qxF "closure: a file of the set is missing: $f" "$d.out"; then echo "ok $f"; else echo "FAIL $f: $(tail -1 "$d.out")"; fi
      mv "$d.gone" "$d/$f" || { echo "FAIL $f: cannot put it back"; exit 1; }
    done' _ "$d" "$@")
    rm -rf "$d" "$d.out" "$d.gone"
  }
  export -f gone
  tr '\n' '\0' < "$SET" | xargs -0 -P "$J" -n $(( ($(wc -l < "$SET") + J - 1) / J )) bash -c 'eval "$BW_DECL"; gone "$@"' _ > "$T/removed"
  ! grep '^FAIL ' "$T/removed" || fail "removing a file of the set did not fail its closure"
  [ "$(grep -c '^ok ' "$T/removed")" = "$(wc -l < "$SET")" ] || fail "not every file was removed in turn"
}

# Bugs: a unit left a process running that had closed every descriptor it inherited (a program that starts another so:
# Python's subprocess), the slot's among them; the slot came back when the unit ended, and the next unit ran beside
# that process, on its core. So did it when the process had started a session of its own, out of the unit's process
# group, with an environment of its own, none of the unit's in it; and for a unit on the run's home slot, whose turn
# alone was kept, the machine's slot came back when the run ended. A unit where the sandbox ends no process (Linux: out
# of the sandbox; macOS: in one, as the install's units are), on a pool of one slot of this case's own, on the core of
# the machine's slot the case holds: the slot stays taken while the process the unit left lives, the run that started
# the unit ended, and is free once the process has ended.
t_left() {
  local BW=() path=$PATH c f=$T/left.slots/1
  [ "$(uname -s)" != Darwin ] || BW=(sandbox-exec -p '(version 1)(allow default)')
  read -ra c <<<"$SLOT_CPUS"
  mkdir -p "$T/tmp" "$T/left.slots" && : > "$f" || fail "cannot make the case's pool"
  leaves() { # <pool|home: the slot the unit runs on> <command..., which leaves a process and writes its id to the file named last>
    local h=$1; shift; rm -f "$T/left.pid"
    ( SLOT_DIR=$T/left.slots SLOT_N=1 SLOT_HOME='' SLOT_CPUS=${c[SLOT_K - 1]:-}
      if [ "$h" = home ]; then exec {SLOT_HOME}>>"$f" && flock -n "$SLOT_HOME" || exit 1; SLOT_HOME_K=1 SLOT_TURN=''; fi
      slot_take; slot_mine
      [ "$h" = pool ] || [ "$CONVEYOR_TEST_SLOT" = "$SLOT_HOME.t" ] || exit 1
      cd "$T" && held "$@" "$T/left.pid" ) || fail "the unit failed ($h)"
    wait_until "[ -s '$T/left.pid' ]" || fail "the unit left no process: the case shows nothing ($h)"
    kill -0 "$(cat "$T/left.pid")" 2>/dev/null || fail "the process the unit left is not running: the case shows nothing ($h)"
    sleep 0.5 # sleep: a holder that waits on nothing has ended by now, and its slot is back; none tells that it stays
    ! flock -n "$f" true || fail "the slot came back while a process of the unit still ran ($h: $1)"
    kill "$(cat "$T/left.pid")"
    wait_until "flock -n '$f' true" || fail "the slot did not come back once the process the unit left had ended ($h: $1)"
  }
  local session='import subprocess, sys; open(sys.argv[1], "w").write(str(subprocess.Popen(["/bin/sleep", "60"], start_new_session=True, env={}).pid))'
  local left='( for ((f = 3; f < 256; f++)); do eval "exec $f>&-"; done; echo "$BASHPID" > "$1"; exec sleep 60 ) > /dev/null 2>&1 &' # sleep: the process the unit leaves, never waited for
  leaves pool bash -c "$left"' until [ -s "$1" ]; do sleep 0.05; done' _
  leaves pool python3 -c "$session"
  leaves home python3 -c "$session"
  # Bug (macOS): the holder asked about the processes of a list (ps's) that left out a process of the unit: one that
  # had ended by the time ps came to it, having started another, in no list yet, before it ended. None was found, and
  # the slot came back with the unit's processes running. Here the unit leaves a chain of processes, each of which
  # starts the next and ends at once, so that every list holds a process that has ended by the time it is asked about
  # and none the holder can find running, until the chain's last one stays.
  local stays='[ "$1" -gt 0 ] || { echo $$ > "$2"; exec /bin/sleep 60; }' # sleep: the process the unit leaves
  printf '%s\n' '#!/bin/sh' "$stays" '"$0" $(($1 - 1)) "$2" &' > "$T/left.chain" && chmod +x "$T/left.chain" || fail "cannot make the chain"
  leaves pool python3 -c 'import subprocess, sys; subprocess.Popen([sys.argv[1], "400", sys.argv[2]], start_new_session=True, env={})' "$T/left.chain"
}

ALL="set required pack left install remove"
SEL=${CONVEYOR_SHELL_TEST_CASE:-$ALL}; SEL=${SEL//,/ }
for CASE in $SEL; do case " $ALL " in *" $CASE "*) ;; *) echo "unknown case $CASE" >&2; exit 2 ;; esac; done
# set, required, pack and left side by side, each holding a test slot; install and remove after, one at a time, as each
# already runs a unit per slot. Each case's output is kept apart and shown in turn once all are done.
for CASE in $SEL; do case $CASE in set|required|pack|left) { slot_take; slot_mine; ( "t_$CASE" ); echo $? > "$T/$CASE.rc"; } > "$T/$CASE.log" 2>&1 & ;; esac; done; wait
# install and remove each run units from the copy on every slot they get, as a whole-suite run does: each takes a
# whole-suite turn (lib/slots.sh slot_whole) before its install is made and its first unit takes a slot, and holds it
# until its last unit has ended (the owner, 2026-11-15: two cards each ran both at once, four whole-suite runs held
# the pool, and the machine's load reached 97 on 16 cores). The wait for a turn is said on the run's stderr. The four
# cases above run only a few units each and take none. A file the set misses fails each at once (install()), with no
# turn waited for.
for CASE in $SEL; do case $CASE in install|remove)
  ( [ -s "$UNREACHED" ] || slot_whole || exit 1;{ ( "t_$CASE" ); echo $? > "$T/$CASE.rc"; } > "$T/$CASE.log" 2>&1 ) \
    || { echo "FAIL [$CASE]: no whole-suite turn" >&2; exit 1; } ;; esac; done
for CASE in $SEL; do cat "$T/$CASE.log"; [ "$(cat "$T/$CASE.rc")" = 0 ] || exit 1; echo "ok $CASE"; done
