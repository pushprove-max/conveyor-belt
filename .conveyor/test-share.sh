# SPDX-License-Identifier: Apache-2.0
# shellcheck shell=bash
# The share of the temp space each test file gets, for the suites that run test files: the full suite
# (.conveyor/test-full.sh) and the card's test step (.conveyor/test-changed.sh), which source this file. A run with no
# share filled a 31 GB /tmp, and 155 files failed with "Disk quota exceeded" (#1238). Each file runs with a TMPDIR of
# its own, removed when it ends (share_run), and a file that writes past its share there (the host file's testTmpMB,
# docs/setup.md) fails alone, with the reason: the other files and the belt keep their space. Writes in the checkout
# count to the share too, once the file has ended (share_run). A file starts only when
# the space holds a share for it beside the shares of the files that run there, in this run or in another one
# (share_noroom, share_take), and it waits for one that runs to end, or fails.

# share_init <folder>: SHARE (the share in MB), LIMKB (in KB), SPACE (the mount point of the space <folder> is in) and
# SHARE_DIR (below); when the host file's testTmpMB is not a whole number of MB from 1, it prints why and fails.
share_init() {
  local host=${XDG_CONFIG_HOME:-$HOME/.config}/conveyor/host.json
  SHARE=2048; [ ! -e "$host" ] || SHARE=$(jq -r '.testTmpMB // 2048' "$host" 2>/dev/null)
  [[ $SHARE =~ ^[1-9][0-9]{0,6}$ ]] || { echo "the host file's testTmpMB ($host) is '$SHARE', or the file cannot be read: it must be a whole number of MB from 1"; return 1; }
  LIMKB=$((SHARE * 1024))
  SPACE=$(df -Pk "$1" 2>/dev/null | awk 'NR == 2 { print $NF }'); SPACE=${SPACE:-$1}
  # The shares folder (share_others): shares/ in the machine's test slots' folder (conveyor/lib/slots.sh,
  # the library CONVEYOR_TEST_SLOTS names, else the checkout's), found here, as a serial suite reads no slots; empty
  # when the library cannot be read.
  SHARE_DIR=''
  # shellcheck source=/dev/null
  if . "${CONVEYOR_TEST_SLOTS:-conveyor/lib/slots.sh}" 2>/dev/null; then
    SHARE_DIR=$(slot_pool > /dev/null 2>&1 && echo "$SLOT_DIR/shares")
  fi
  return 0
}

# share_quota <folder>: the KB left of this user's block quota on the space <folder> is in, printed; fails when the
# space has no quota for the user (or no hard limit), or it cannot be read (macOS, a kernel before quotactl_fd: Linux
# 5.14, tmpfs from 6.6).
share_quota() {
  python3 -I - "$1" 2>/dev/null <<'EOF'
import ctypes, os, sys
if not sys.platform.startswith("linux"):
    sys.exit(1)
class Dqblk(ctypes.Structure):  # struct if_dqblk: limits in 1 KB blocks, dqb_curspace in bytes
    _fields_ = [(n, ctypes.c_uint64) for n in ("bhard", "bsoft", "space", "ihard", "isoft", "inodes", "btime", "itime")] + [("valid", ctypes.c_uint32)]
d = Dqblk()
fd = os.open(sys.argv[1], os.O_RDONLY)
# syscall 443, quotactl_fd, on every Linux architecture; Q_GETQUOTA (0x800007) of USRQUOTA, the user's own quota.
if ctypes.CDLL(None, use_errno=True).syscall(ctypes.c_long(443), fd, ctypes.c_uint(0x800007 << 8), os.getuid(), ctypes.byref(d)) != 0:
    sys.exit(1)
if not d.valid & 1 or d.bhard == 0:  # QIF_BLIMITS unset, or no hard limit: no quota to keep to
    sys.exit(1)
print(max(d.bhard - (d.space + 1023) // 1024, 0))
EOF
}

# share_free <folder>: the KB this user can still write under <folder>, printed: the space's free blocks (df), or what
# is left of the user's block quota there (share_quota) when that is less: a /tmp mounted with usrquota fails a write
# at the quota while df still shows free space. Fails when df gives no number.
share_free() {
  local f q
  f=$(df -Pk "$1" 2>/dev/null | awk 'NR == 2 { print $4 }')
  [[ $f =~ ^[0-9]+$ ]] || return 1
  q=$(share_quota "$1") && [[ $q =~ ^[0-9]+$ ]] && [ "$q" -lt "$f" ] && f=$q
  echo "$f"
}

# share_others <folder>: the KB, printed, of the shares that files running on the space hold (share_take), less those of
# the run whose folder is <folder> (a file's temp folder is in its run's) and those of a file whose temp folder holds
# <folder> (a run started inside a test file writes in that file's share). A share is a file of the shares folder,
# SHARE_DIR (share_init), so the runs of every checkout count each other's files: two runs that each counted only their
# own files started more than the space held (#1394). A share no process holds an flock on (slot_held: its run was
# killed) counts for nothing. 0 for a run with no shares folder.
share_others() {
  local f k s ft n=0
  [ -n "${SHARE_DIR:-}" ] || { echo 0; return 0; }
  for f in "$SHARE_DIR"/r.*; do
    { [ -f "$f" ] && IFS=$'\t' read -r k s ft < "$f"; } 2>/dev/null || continue
    [[ $k =~ ^[0-9]+$ ]] && [ "$s" = "$SPACE" ] && [ "${ft%/*}" != "$1" ] && [[ $1/ != "$ft"/* ]] && slot_held "$f" && n=$((n + k))
  done
  echo "$n"
}

# share_noroom <folder> <n> [<KB>]: why a file cannot start under <folder> while <n> other files of the run still run,
# printed, or exit 1 when it can: the space this user can still write there must hold a share for each of them (each
# may grow to its share), its own share (LIMKB) for the file, one kept for the belt and <KB> (0), the shares other
# files hold there, of this run or of another (share_take).
share_noroom() {
  local f o=${3:-0} need
  need=$((($2 + 1) * SHARE * 1024 + LIMKB + o))
  f=$(share_free "$1") || { echo "the free space under $SPACE could not be read (df), so it is not known to hold the file's share"; return 0; }
  [ "$f" -lt "$need" ] || return 1
  echo "$((f / 1024)) MB is free to this user under $SPACE (its free space, or what is left of the user's quota there when that is less), and it needs $((need / 1024)) MB there: a share (the host file's testTmpMB, $SHARE MB) for each of the $2 file(s) running, one for it and one kept for the belt$([ "$o" = 0 ] || echo ", and $((o / 1024)) MB for the other files that run there (of this run or of another: a suite, a card's test step)")"
}

# share_take <temp folder>: takes the share of the file that runs in <temp folder>, a file of the shares folder
# (share_others) that this shell holds an flock on through SHARE_FD, named in SHARE_RES; what the file starts inherits
# the descriptor, so the share is held until the last of them ends. The room, beside the shares the other files hold
# there, of this run or of another, is checked and the share taken under the folder's lock, so two runs never both
# take the last room. While there is no room and a file holds a share there, it waits for one to end; with none, it
# fails, and SHARE_WHY says why. With no shares folder it only checks the room.
share_take() {
  local d=${SHARE_DIR:-} l f o
  SHARE_RES=''
  if [ -z "$d" ]; then SHARE_WHY=$(share_noroom "$1" 0) && return 1; return 0; fi
  mkdir -p "$d" 2>/dev/null || { SHARE_WHY="the shares folder $d could not be made"; return 1; }
  while :; do
    { exec {l}>> "$d/lock" && flock -w 60 "$l"; } 2>/dev/null || { SHARE_WHY="the lock of the shares folder $d could not be taken"; return 1; }
    # A share no process holds is left by a run that was killed: it is removed, under the lock, as none is made then.
    for f in "$d"/r.*; do [ ! -f "$f" ] || slot_held "$f" || rm -f "$f"; done
    o=$(share_others "$1")
    if ! SHARE_WHY=$(share_noroom "$1" 0 "$o"); then
      { SHARE_RES=$(mktemp "$d/r.XXXXXX") && exec {SHARE_FD}>> "$SHARE_RES" && flock "$SHARE_FD" \
        && printf '%s\t%s\t%s\n' "$LIMKB" "$SPACE" "$1" > "$SHARE_RES"; } 2>/dev/null \
        || { SHARE_WHY="its share could not be kept in $d"; exec {l}>&-; return 1; }
      exec {l}>&-; return 0
    fi
    exec {l}>&-
    [ "$o" != 0 ] || return 1
    sleep 0.5
  done
}

# share_guard <temp folder> <pid file> <mark>: stops the test file that <pid file> names once its temp folder holds its
# share or more, as the size limit (ulimit -f, share_run) caps one file but not many: TERM to it and its children,
# KILL 10 s later. <mark> keeps the folder's size then, for share_run's reason. It looks once the file has started and
# then every 0.1 s: a look each 1 s let a file write a share and more before the first look (#1394). It first closes
# every descriptor from 3 up it inherited: its `sleep` runs on for up to 0.1 s after share_run kills it, and held the
# test file's slot (the lock its worker inherits, conveyor/lib/slots.sh) that long, so the suite's next file waited.
share_guard() {
  local p='' k f
  for f in /dev/fd/*; do f=${f##*/}; [[ $f =~ ^[0-9]+$ ]] && [ "$f" -ge 3 ] && eval "exec $f>&-" 2>/dev/null; done
  while :; do
    if [ -n "$p" ] || read -r p < "$2"; then
      k=$(du -sk "$1"); k=${k%%[[:space:]]*}
      if [ "${k:-0}" -ge "$LIMKB" ]; then
        echo "$k" > "$3"; pkill -TERM -P "$p"; kill -TERM "$p"; sleep 10; pkill -KILL -P "$p"; kill -KILL "$p"; return 0
      fi
    fi
    sleep 0.1 || return 0
  done 2>/dev/null
}

# share_run <label> <folder> <command>...: runs one test file's command (a function, or a program it execs) with
# TMPDIR <folder>, made here and removed when it ends, no one file it writes larger than its share (ulimit -f, in KB
# in bash) and stopped once the folder holds its share (share_guard). It prints the command's output, then, when the
# folder reached its share (also when the command ended by itself between the guard's looks), `<label> wrote ...`
# with the share and the space, and exits with the command's status, or 1 then. The same when the files new in the
# checkout ($PWD) and the folder hold its share together, or one new file there is at the size limit: these are seen
# only once the command has ended, and a file run beside it in a parallel suite that wrote them while it ran fails it
# too, as nothing tells which file wrote them. The command starts only once its share is taken (share_take, which
# waits for room): when it cannot be, `<label> did not start: <why>` and exit 1. A TERM, INT or HUP to it is passed to
# the command, and the folder is still removed; a run stopped with KILL leaves the folder to its caller's own temp
# folder, which <folder> is in. It runs in a subshell of its own, so its traps are not its caller's.
share_run() (
  local label=$1 ft=$2 g c='' k st o f pr; shift 2
  mkdir "$ft" || { echo "$label did not start: its temp folder $ft could not be made"; return 1; }
  trap 'rm -rf "$ft"; exit 143' TERM INT HUP
  share_take "$ft" || { echo "$label did not start: $SHARE_WHY"; rm -rf "$ft"; return 1; }
  trap '[ -z "$c" ] || kill -TERM "$c" 2>/dev/null' TERM INT HUP
  share_guard "$ft" "$ft.pid" "$ft.over" > /dev/null 2>&1 < /dev/null & g=$!
  ( echo "$BASHPID" > "$ft.pid"; ulimit -f "$LIMKB" 2>/dev/null; export TMPDIR=$ft
    if [ "$(type -t "$1")" = function ]; then "$@"; else exec "$@"; fi ) & c=$!
  # A wait a signal cut short is waited again until the command has ended.
  while wait "$c"; st=$?; kill -0 "$c" 2>/dev/null; do :; done
  kill "$g" 2>/dev/null; wait "$g" 2>/dev/null
  k=$(du -sk "$ft" 2>/dev/null | cut -f1); [ ! -s "$ft.over" ] || read -r k < "$ft.over"
  # The files new in the checkout ($PWD, its .git and the folder <folder> is in left out) since the command started:
  # the size limit kills only the command that writes, so a test whose last command passes exits 0 with a file cut at
  # its share there, and a test can write many files there that each stay under the limit (#1394).
  pr=(find "$PWD" \( -path "$PWD/.git" -o -path "${ft%/*}" \) -prune -o -type f -newer "$ft.pid")
  o=$("${pr[@]}" -exec du -k {} + 2>/dev/null | awk '{ s += $1 } END { print s + 0 }')
  while IFS= read -r f; do
    echo "$label wrote a file larger than its share, or one the size limit (ulimit -f) cut at its share of $LIMKB KB (the host file's testTmpMB, $SHARE MB): $f: it fails, or a file run beside it wrote it"; st=1
  done < <("${pr[@]}" -size +$((LIMKB * 1024 - 1))c -print 2>/dev/null)
  if [ "${k:-0}" -ge "$LIMKB" ]; then
    echo "$label wrote $k KB in its temp folder, and its share of the space under $SPACE is $LIMKB KB (the host file's testTmpMB, $SHARE MB): it fails"; st=1
  elif [ $((${k:-0} + o)) -ge "$LIMKB" ]; then
    echo "$label wrote $o KB in $PWD, outside its temp folder, and ${k:-0} KB in it, and its share of the space is $LIMKB KB (the host file's testTmpMB, $SHARE MB): it fails, or a file run beside it wrote them"; st=1
  fi
  # u+w: the folder may hold read-only folders (an install), which rm cannot empty.
  chmod -R u+w "$ft" 2>/dev/null; rm -rf "$ft" "$ft.pid" "$ft.over" ${SHARE_RES:+"$SHARE_RES"}
  return "$st"
)
