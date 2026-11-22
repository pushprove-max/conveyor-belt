# SPDX-License-Identifier: Apache-2.0
# The projects of this machine, "<repo> TAB <main> TAB <engine>" one a line: the host file's records (as the Foreman
# reads them, foreman/lib.sh records), or, when it has no records key, this checkout alone; none when its records are
# an empty list (the last project was removed). <engine> is "checkout" for a record run from its own checkout's code
# (its "engine": "checkout": the plugin's own belt, whose pack names no plugin to follow or pin), else empty. Fails,
# saying why, when they do not read: the whole file is read, so one cut short or with anything after its one value is
# not taken for a file with no records; an engine other than "checkout" does not read either, so a record mistyped is
# never run on another engine than the one it names.
projects() {
  jq -rs --arg r "$REPO" --arg m "$MAIN" 'if length == 1 then .[0] else error("not one value") end | (.records // [{repo: $r, main: $m}])
    | if type == "array" and all(type == "object" and (.repo | type == "string" and test("^[A-Za-z0-9._-]+$"))
        and (.main | type == "string" and startswith("/")) and (.engine | . == null or . == "checkout")) and (map(.repo) | unique | length) == length then .[] else error("records") end
    | "\(.repo)\t\(.main)\t\(.engine // "")"' "$HOST" 2>/dev/null \
    || { [ ! -e "$HOST" ] && printf '%s\t%s\t\n' "$REPO" "$MAIN"; } || { echo "conveyor: the records of $HOST are not understood" >&2; return 1; }
}
# conveyor.sh machine: the machine's one Conveyor (docs/setup.md, Run). One a machine (MACH/run's lock; MACH/loop.json names
# it, for doctor): it keeps one loop running for each project of the host file's records, each `serve` in its own
# main checkout, on its own state folder, cards folder, pack, pin, issue repo and push, so nothing of one project is
# read or written by another's card; the machine's cap and room (room()) are over them all. A record added is
# served from the next turn; a loop whose record is gone is stopped; a loop that ends is started again after
# MACHINE_RESTART seconds. Each loop's output is its lines with its repo in front. TERM ends every loop and all under
# it (its cards, their sessions, reviews and tests), then this, within seconds (machinestop); a TERM sent while its
# service runs, by no stop of it, ends nothing (machinenostop). Any other end (INT too) says why, on its last line
# (machineend).
# A loop runs the machine's own Conveyor (this file's), which restarts it on its project's pin or taken commit; a
# record run from its own checkout ("engine": "checkout") runs that checkout's conveyor.sh instead, which restarts on
# the checkout's new code as its HEAD moves to a commit that changes engine code (stale(), lib/install.sh). A record
# whose engine changes is a record gone and one added: its loop is stopped and started again on the other.
MACHINE_POLL=5 MACHINE_RESTART=10
# <pid>...: ends each of them and every process under it. Each is stopped before the processes under it are listed
# (freeze), so none starts another unseen; all are then told TERM and go on, and those still there 3 s later are
# killed, with all they started since. One started on TERM by a process that then ended is under none of them any
# more: it is still in its starter's process group, and every group of theirs is killed whole. Each loop is a group
# of its own (machineloop), and so is each session, review and test (timeout's), so none of those groups holds a
# process the machine's Conveyor did not start; its own group is never one of them. They go on from the last listed
# to the first, each before the one that started it: a group whose members are stopped as the process over it ends is
# given HUP by the system, and a session would end on that before it has handled its TERM.
# One started on TERM in a group of its own (setsid) by a process that then ended is in none of those groups either:
# it is found as machineleft finds it, and killed with all under it, again until none is left. Then the loops'
# output, which nothing writes to any more, is given a moment to be written out by its readers (MACHINE_READERS).
machinestop() {
  local all grp i=0 p back='' left
  all=$(for p in "$@"; do freeze "$p"; done)
  if [ -n "$all" ]; then
    grp=$(ps -o pgid= -p "$(paste -sd, - <<<"$all")" 2>/dev/null | tr -d ' ' | sort -u | grep -vx "$(ps -o pgid= -p $$ | tr -d ' ')")
    for p in $all; do back="$p $back"; done
    kill -TERM $all 2>/dev/null; kill -CONT $back 2>/dev/null
    # One that has ended and is not waited for yet is still listed (Z): it is gone.
    while ps -o stat= -p "$(paste -sd, - <<<"$all")" 2>/dev/null | grep -qv Z && [ $((i++)) -lt 30 ]; do sleep 0.1; done
    kill -KILL $(for p in $all; do freeze "$p"; done) 2>/dev/null
    for p in $grp; do kill -KILL -- "-$p" 2>/dev/null; done
  fi
  i=0; while left=$(machineleft); [ -n "$left" ] && [ $((i++)) -lt 20 ]; do kill -KILL $(for p in $left; do freeze "$p"; done) 2>/dev/null; done
  i=0; while kill -0 $MACHINE_READERS 2>/dev/null && [ $((i++)) -lt 10 ]; do sleep 0.1; done
}
# What this process started that is under nothing it knows any more (its parent ended): on Linux its own children
# (it is their subreaper: machineloop), but the readers of its loops' output; and every process that carries its mark
# in its environment (MACHINE_MARK: all it started and all those started, where they kept it; the only way to find
# one where no process can be made a subreaper, macOS). Asked in a $( ): the mark is taken out there, or the programs
# that look for it would carry it themselves. One that has ended and is not waited for yet (Z) is gone. The reader of
# its own stderr (machineerr, MACHINE_ERRPID) is never one: it ends with this process, once it has written this
# process's last line (machineend, which waits for it) or, on the stop, which says nothing, once that stderr closes.
machineleft() {
  local me=$BASHPID m=$MACHINE_MARK
  unset "${m%%=*}"
  { ps -axo pid=,ppid=,stat= | awk -v p=$$ -v me="$me" -v rd="$MACHINE_READERS " '$2 == p && $1 != me && $3 !~ /^Z/ && !index(rd, " " $1 " ") { print $1 }'
    ps axeww -o pid=,args= | awk -v m="$m" 'index($0 " ", " " m " ") { print $1 }'; } | sort -u | grep -vxF "${MACHINE_ERRPID:-}"
}
# Whether this process is the child subreaper of what it starts (Linux). No process can read that of itself but by
# prctl, which bash cannot call, so it is tried: a process whose parent has ended has this process as its parent
# only when it is that (or is the first process of its PID namespace, which is the same to those under it).
subreaper() {
  [ "$(python3 -I -c 'import os, sys, time
p = os.getpid()
if os.fork(): os._exit(0)
while os.getppid() == p: time.sleep(0.001)
print(int(os.getppid() == int(sys.argv[1])))' $$)" = 1 ]
}
# Whether a TERM is no stop: this process is the main process of its service (conveyor-machine, as install-service
# names it: its MainPID) and the service is active, so no stop or restart of it sent the TERM (either has the service
# deactivating before the TERM is handled). Such a TERM came from a process on this machine: a card's build session
# killed the parent of a process it had started in the background, and that process had outlived its shell, so its
# parent was this one (the reaper of all it starts, machineloop); the machine then ended with every loop and card
# (#1332). It says so, and the machine goes on. Anywhere else (no systemd, a process that is not the service's own, a
# service that is stopping or that systemctl does not answer for) a TERM is a stop.
machinenostop() {
  local o
  command -v systemctl >/dev/null && o=$(timeout 10 systemctl --user show -p MainPID -p ActiveState conveyor-machine.service 2>/dev/null) \
    && grep -qx "MainPID=$$" <<<"$o" && grep -qx 'ActiveState=active' <<<"$o" || return 1
  echo "conveyor: the machine's Conveyor was sent TERM while its service conveyor-machine runs, so by no stop of the service: it goes on (systemctl --user stop conveyor-machine stops it)" >&2
}
# The machine's stop, on TERM (but one machinenostop takes for none): its loops and all under them are ended
# (machinestop), then it, with no line. Called in machineloop's traps, as machinesig, in its variables (kid, nap).
machinedown() { trap '' TERM INT; trap - EXIT; machinestop "${!kid[@]}" $nap; exit 0; }
# Its end on a signal other than TERM (INT, as Ctrl+C sends, too): its loops and all under them are ended as on its
# stop, and its last line names the signal (machineend).
machinesig() { # <signal>
  trap '' TERM INT; MACHINE_WHY="it was sent SIG$1"; machinestop "${!kid[@]}" $nap; exit $((128 + $(kill -l "$1")))
}
# The machine's last line when it ends, but on its stop: why it ends. A signal (machinesig), else its exit status and
# the command it ended at, with the error the shell ended on (a variable not set, under set -u), which the shell
# writes on the line before: its reader (machineerr) puts that error on this line. It waits (2 s at most) until the
# reader has written it, so this line is out before the process ends.
machineend() { # <exit status> <the command>
  local i=0
  echo "conveyor: the machine's Conveyor ends: ${MACHINE_WHY:-"exit status $1 at the command: $2"}" >&2
  while ps -o stat= -p "${MACHINE_ERRPID:-0}" 2>/dev/null | grep -qv Z && [ $((i++)) -lt 20 ]; do sleep 0.1; done
}
# The reader of the machine's own stderr (machineloop): each line goes on as it is, at once. Its last line
# (machineend) ends it; when that line gives an exit status and the line before it is the shell's own error
# ("<file>: line <n>: <error>"), the error that ended the shell, the line names that error first. It ignores the
# signals that end the machine (Ctrl+C sends INT to the whole group), so it is still there to write that line, which
# the machine waits for before it ends (machineend). It holds no lock (fd 8), so a reader that outlives that wait
# keeps no next machine from starting.
machineerr() {
  local l='' p
  trap '' TERM INT HUP; exec 8>&-
  while IFS= read -r p; do
    [[ $p != "conveyor: the machine's Conveyor ends: exit status "* || ! $l =~ :\ line\ [0-9]+:\ (.+)$ ]] \
      || p="conveyor: the machine's Conveyor ends: the shell's error \"${BASH_REMATCH[1]}\", ${p#"conveyor: the machine's Conveyor ends: "}"
    printf '%s\n' "$p" >&2
    [[ $p != "conveyor: the machine's Conveyor ends: "* ]] || exit 0
    l=$p
  done
}
machineloop() {
  local -A kid=() at=() rec=(); local recs known r m e p o nap='' why told=''
  # On Linux this process is the child subreaper of all it starts (prctl, set through python3 and kept by the bash it
  # then becomes: this file, run again): a process left with no parent, whatever group or session it made and
  # whatever it took out of its environment, is this process's own child, and is ended with it (machinestop).
  # Whether it is that already is asked of the kernel (subreaper), never read from its environment, which whoever
  # starts it sets: a variable that said so left it no subreaper, and the processes left with no parent ran on.
  # python3 starts with SIGPIPE and SIGXFSZ ignored, and every loop and session under it would run so: each is as
  # this process has it. This exec and each loop's start leave out the copy of stderr (LOGFD): the conveyor.sh each
  # becomes makes its own, so a copy kept is one more fd held for good by the machine, its loops and their cards.
  if [ "$(uname -s)" = Linux ] && command -v python3 >/dev/null && ! subreaper; then
    exec python3 -I -c 'import ctypes, os, signal, sys
if ctypes.CDLL(None).prctl(36, 1):  # PR_SET_CHILD_SUBREAPER
    sys.exit("conveyor: the machine\x27s Conveyor cannot be made the reaper of the processes it starts (prctl)")
for s in signal.SIGPIPE, signal.SIGXFSZ:
    if not int(sys.argv[1], 16) >> (s - 1) & 1: signal.signal(s, signal.SIG_DFL)
os.execvp(sys.argv[2], sys.argv[2:])' "$(sed -n 's/^SigIgn:[[:space:]]*//p' "/proc/$$/status")" "$BASH" "$HERE/conveyor.sh" machine {LOGFD}>&-
  fi
  MACHINE_MARK=CONVEYOR_MACHINE_ID=$$.$RANDOM$RANDOM MACHINE_READERS=''; export "$MACHINE_MARK"
  mkdir -p "$MACH" || return 1
  exec 8>>"$MACH/run"
  flock -n 8 || { echo "conveyor: the machine's Conveyor already runs ($(jq -r '"pid \(.pid)"' "$MACH/loop.json" 2>/dev/null)); a second one would pass the machine cap" >&2; exit 1; }
  # Its commit (none from a checkout), so no project's prune() removes the install the service runs.
  jq -cn --argjson p "$$" --arg t "$(p_started $$)" --arg c "$OWN" '{pid: $p, started: $t} + (if $c == "" then {} else {commit: $c} end)' > "$MACH/loop.json"
  # The stop (TERM) says nothing of itself; every other end says why (machineend, machinesig), its stderr read by
  # machineerr, which machineleft does not count as left.
  exec 2> >(machineerr); MACHINE_ERRPID=$!
  MACHINE_WHY=''; trap 'machinenostop || machinedown' TERM; trap 'machineend "$?" "$BASH_COMMAND"' EXIT
  trap 'machinesig INT' INT; trap 'machinesig HUP' HUP; trap 'machinesig QUIT' QUIT; trap 'machinesig USR1' USR1; trap 'machinesig USR2' USR2; trap 'machinesig ALRM' ALRM
  while :; do
    # Records that do not read stop no loop (the file may be half written); records read as none stop every loop.
    # Why they do not is said when it changes, never at every turn (as the loop's own reason is: run, told).
    known=1 why=''; recs=$(projects 2>/dev/null) || { known=''; why=$(projects 2>&1 >/dev/null) || :; why=${why:-$told}; }
    [ "$why" = "$told" ] || { told=$why; [ -z "$why" ] || printf '%s\n' "$why" >&2; }
    for p in "${!kid[@]}"; do
      r=${kid[$p]}
      if ! kill -0 "$p" 2>/dev/null; then wait "$p" 2>/dev/null; unset 'kid[$p]'; at[$r]=$SECONDS; echo "conveyor: the loop of $r ended; it starts again in ${MACHINE_RESTART}s"
      elif [ -n "$known" ] && ! grep -qxF "${rec[$r]}" <<<"$recs"; then kill -TERM "$p" 2>/dev/null; echo "conveyor: $r is no longer a record of $HOST: its loop is stopped"; fi
    done
    while IFS=$'\t' read -r r m e; do
      [ -n "$r" ] || continue
      for p in "${!kid[@]}"; do [ "${kid[$p]}" != "$r" ] || continue 2; done
      [ -z "${at[$r]:-}" ] || [ $((SECONDS - ${at[$r]})) -ge "$MACHINE_RESTART" ] || continue
      rec[$r]=$r$'\t'$m$'\t'$e
      # The reader of the loop's output is this process's own child, in its group: it is not ended with the loop,
      # and writes out the loop's last lines (machinestop).
      exec {o}> >(exec 8>&-; while IFS= read -r p; do printf '%s: %s\n' "$r" "$p"; done); MACHINE_READERS+=" $!"
      set -m # job control, for the loop's start alone: the loop is a process group of its own (machinestop)
      ( set +m; cd "$m" 2>/dev/null || { echo "conveyor: the checkout $m of $r is not there" >&2; exit 1; }
        unset CONVEYOR_CARDS CONVEYOR_ADOPT CONVEYOR_KIDS
        if [ "$e" = checkout ]; then e=$m/conveyor/conveyor.sh; else e=$HERE/conveyor.sh; fi
        CONVEYOR_MAIN=$m exec "$BASH" "$e" serve ) 8>&- {LOGFD}>&- >&"$o" 2>&1 {o}>&- &
      kid[$!]=$r; set +m; exec {o}>&-
    done <<<"$recs"
    sleep "$MACHINE_POLL" 8>&- & nap=$!; wait $nap
  done
}
# conveyor.sh machine pause | resume: the whole machine's pause, the host file's mode (mhost()): paused, no project
# starts a new card (room()); cards already running finish. No project's own control record is touched. Under the
# machine's lock, as hostput, and under the host file's own ($HOST.lock, which a lane's note holds while it reads and
# replaces the file: lanenote), so neither writes its older reading over the other's change: the host file read and
# written whole (made, as {}, when there is none); one that does not read as an object is left as it is.
machinemode() { # <pause | resume>
  local f='if $a == "pause" then .mode = "pause" else del(.mode) end'
  mkdir -p "${HOST%/*}" || return 1
  ( flock -w 30 9 || exit 1
    [ -e "$HOST" ] || echo '{}' > "$HOST" || exit 1
    jq -es 'length == 1 and (.[0] | type) == "object"' "$HOST" >/dev/null 2>&1 \
      || { echo "conveyor: the host file $HOST does not read as one object: the machine's Conveyor is not changed" >&2; exit 1; }
    t=$(mktemp "$HOST.XXXXXX") || exit 1
    jq --arg a "$1" "$f" "$HOST" > "$t" && mv "$t" "$HOST" || { rm -f "$t"; exit 1; }
  ) 9>>"$HOST.lock" || return 1
  if [ "$1" = pause ]; then echo "conveyor: the machine's Conveyor is paused: no project starts a new card (cards running finish)"
  else echo "conveyor: the machine's Conveyor runs again: each project picks as its own record says"; fi
}
