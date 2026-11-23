# SPDX-License-Identifier: Apache-2.0
# The machine a release's whole suite runs on (relsuite(), commands/release-prep.sh; docs/releases.md, Where the suite
# runs). The control record's suiteMachine is the rule: {kind: "local"}, this machine (the default, also when the record
# has none), {kind: "ssh", target: <user@host>, dir: <folder there>}, a Linux box over ssh, or {kind: "devbox", size, tag,
# idleStop, and box when the owner named a devbox they already have}, a Namespace Devbox leased for the run (or that box), set with `conveyor.sh control suite-machine`. `release-run ... --machine local` runs one run here whatever the rule says (releasego() is
# given CONVEYOR_RELEASE_MACHINE=local). A run goes through its steps in order, each named in the run's record as it
# begins (machine.step, then done) with the seconds of each step that ended (machine.secs):
# - start: local, nothing. ssh: the box answers over ssh with no password asked, has bash 5.1 or later, jq and git, and its
#   test slots are read (HOSTFACTS): the most files a parallel suite runs at once there (relatonce()). devbox: the login
#   to Namespace is checked ("Not logged in to Namespace" ends the run), `devbox acquire <tag> --size <size>
#   --auto_stop_idle_timeout <idleStop>` leases a devbox, whose lease id is kept (SH_LEASE, and machine.lease in the
#   record), and the devbox is checked as a box over ssh is, each command sent by `devbox exec --lease_id <id>`. With
#   a box named in the rule (box), no devbox is acquired: `devbox exec <box> -- true` starts that box, the box is kept
#   in the record (machine.box), and each command is sent by `devbox exec <box> --`; it is never given back.
# - setup: local, nothing. ssh: the tested commit's .conveyor/test-machine.sh runs there when its blob is not the one the
#   box last ran (<dir>/<repo>/setup.blob); with no such file it is skipped.
# - checkout: the worktree of the commit here ($CARDS/release/wt, deps()), which the changed-tests selection and the
#   records read. ssh: also a git bundle of the commit, sent on ssh's input and checked out in <dir>/<repo>/wt (the box
#   needs no clone access and is given no GitHub token), then the pack's worktree.setup run there.
# - run: local, tests() on this machine's test slots. ssh: test.full started there with nohup (each run alone of a
#   failed case too, fullalone()), told the run's CONVEYOR_SUITE_* and its log folder; a poller copies its output and
#   log folder back to <worktree>.test and <worktree>.testlog at least every 10 s and writes <worktree>.live, so the
#   records, the snapshot, the reruns (suitereuse()) and the flaky rule read the same files as of a run here. A run
#   there takes no test slot of this machine (a devbox's run is started with `devbox exec -d`); one that ends past a run here's time limit (testTimeout) timed out, and
#   one still going a poll's time past it is stopped there.
# - results: the box's run files are cleared (an ssh box's), and a devbox's lease is given back (`devbox release
#   --lease_id <id>`), as it is when any step fails, and by `release-run stop`; a devbox the run never gives back stops
#   itself when idle (idleStop).
# A start, setup or checkout that fails ends the run "not started": its reason goes in machine.reason and the record's
# reasons, nothing runs, and the suite never moves to another machine by itself. `release-run stop` stops the run
# there too (hoststop()). The record's machine is {kind, name (for people: "this machine", or the ssh host), target
# and dir (ssh's, else null), lease (a devbox's, else null), step, secs, reason}; a devbox's name is "Namespace Devbox
# <size>". Sourced by commands/release-prep.sh and commands/suite-machine.sh.
SH_KIND=local SH_NAME='this machine' SH_POST='the build machine' SH_TARGET='' SH_DIR='' SH_D='' SH_SLOTS='' SH_STEP='' SH_T=0 SH_WHY=''
SH_SIZE='' SH_TAG='' SH_IDLE='' SH_LEASE='' SH_BOX=''
# What every check of a box prints, one fact a line: its bash version, each tool named (ok or missing), its CPUs and
# its test slots: slot_pool's there, of lib/slots.sh sent on ssh's input and read from that stream, never reopened by path (some ssh servers refuse that) (hostfacts()), so its host file's testSlots
# and its cores cap them as the suite's runner there finds them (.conveyor/test-full.sh), never its CPU count alone.
HOSTFACTS='printf "bash\t%s\n" "${BASH_VERSINFO[0]}.${BASH_VERSINFO[1]}"
for t; do printf "tool\t%s\t%s\n" "$t" "$(command -v "$t" > /dev/null && echo ok || echo missing)"; done
printf "cpus\t%s\n" "$(nproc 2> /dev/null || getconf _NPROCESSORS_ONLN 2> /dev/null || echo 0)"
printf "slots\t%s\n" "$(eval "$(cat)" > /dev/null 2>&1 && slot_pool > /dev/null 2>&1 && echo "$SLOT_N")"'
# The suite's run on the box (hosttests()), given its <command>, <time limit> and the box's <name>: its exit in wt.rc,
# timed by the box's own clock, which starts before this machine's: a run that ends past the limit, even with 0, has
# 124, the exit of a run here that timed out, and its output says so.
HOSTRUN='bash -c "$1" > ../wt.test 2>&1 < /dev/null; r=$?
[ "$SECONDS" -lt "$2" ] || { r=124; echo "conveyor: the suite ran past its time limit, $2 s (testTimeout), on $3" >> ../wt.test; }
echo "$r" > ../wt.rc'
# The suite's run on the box stopped: its process group, which setsid made, else its process. It prints
# "conveyor-kill: stopped" when it was stopped, "conveyor-kill: ended" when there was none to stop (the run had ended, or
# none started): its output, not its exit, as `devbox exec` gives 1 for any exit of its command but 0.
HOSTKILL='r=ended; p=$(cat "$D/wt.pid" 2> /dev/null) && { kill -TERM -- -"$p" 2> /dev/null || kill -TERM "$p" 2> /dev/null; } && r=stopped; rm -f "$D/wt.pid"; echo "conveyor-kill: $r"'
# The jq filter of a release record's machine whose suite's run `release-run stop` stops (hoststop()): a box over ssh, or
# a devbox leased or named, whose step is not done; empty for any other record.
HOSTLIVE='.machine | objects | select((.kind == "ssh" or (.kind == "devbox" and (((.lease // "") | length > 0) or ((.box // "") | length > 0)))) and .step != "done")'
# The run on the rule's box stopped (HOSTKILL), in words: stopped, ended, or not reached <via> (' over ssh' or nothing),
# which fails.
hostkill() { # <via>
  local o
  o=$(hostssh "$SH_D; $HOSTKILL" 30 < /dev/null 2> /dev/null)
  case $'\n'$o$'\n' in
    *$'\nconveyor-kill: stopped\n'*) echo 'was stopped there' ;;
    *$'\nconveyor-kill: ended\n'*) echo 'had already ended there' ;;
    *) echo "could not be reached$1 to stop it; it may still run there"; return 1 ;;
  esac
}
# The seconds one poll of the run on the box may take (hosttests()): its 10 s wait there, then the copy of its output.
HOSTPOLL=60
# <text> in single quotes, as any POSIX shell reads it: the box's login shell is not always bash.
hostq() { printf "'%s'" "${1//\'/\'\\\'\'}"; }
# <script> run by bash on the rule's box, its input ssh's: no password is asked (BatchMode), at most 20 s to connect,
# and a link that stops answering ends it in 30 s (ServerAlive). With <seconds>, ssh is ended then (exit 124), so a
# box that answers ssh but not the script (a stalled poll) holds no step for longer. On a devbox, the same through `devbox
# exec` on the run's lease, and with <detach> given, `devbox exec -d`, which does not wait for the script.
hostssh() { # <script> [seconds] [detach]
  local t=() d=(); [ -z "${2:-}" ] || t=(timeout --kill-after=5 "$2"); [ -z "${3:-}" ] || d=(-d)
  if [ "$SH_KIND" = devbox ] && [ -n "$SH_BOX" ]; then "${t[@]}" devbox exec "${d[@]}" "$SH_BOX" -- bash -c "$1"; return; fi
  [ "$SH_KIND" != devbox ] || { "${t[@]}" devbox exec "${d[@]}" --lease_id "$SH_LEASE" -- bash -c "$1"; return; }
  "${t[@]}" ssh -o BatchMode=yes -o ConnectTimeout=20 -o ServerAliveInterval=10 -o ServerAliveCountMax=3 -- "$SH_TARGET" "bash -c $(hostq "$1")"
}
# The rule of this run, in SH_KIND, SH_NAME, SH_POST (the name a commit status gives it: a host's name is never
# posted, as the status is public; a devbox's is its name), SH_TARGET, SH_SIZE, SH_TAG, SH_IDLE (a devbox's), SH_DIR and SH_D (the shell line that sets D, the run's folder on the
# box: <dir>/<repo>, a ~ at the start of dir read as the box's $HOME).
hostrule() { # <command name>
  local r
  if [ "${CONVEYOR_RELEASE_MACHINE:-}" = local ]; then r='{"kind":"local"}'
  else r=$(ctl | jq -ce '.suiteMachine | objects') || { echo "conveyor: $1: the control record's suiteMachine cannot be read; nothing run" >&2; return 1; }; fi
  SH_KIND=$(jq -r .kind <<<"$r") SH_TARGET=$(jq -r '.target // ""' <<<"$r") SH_DIR=$(jq -r '.dir // ""' <<<"$r")
  SH_SIZE=$(jq -r '.size // ""' <<<"$r") SH_TAG=$(jq -r '.tag // ""' <<<"$r") SH_IDLE=$(jq -r '.idleStop // ""' <<<"$r") SH_LEASE='' SH_BOX=$(jq -r '.box // ""' <<<"$r")
  # shellcheck disable=SC2034,SC2088 # SH_POST is read by relsuite(), commands/release-prep.sh; the devbox's ~ is its own
  case $SH_KIND in
    ssh) SH_NAME=${SH_TARGET#*@} SH_POST='a Linux box over ssh' ;;
    devbox) SH_NAME="Namespace Devbox $SH_SIZE" SH_POST=$SH_NAME SH_DIR='~/conveyor-suite'
      # A named box: its size is the box's own, and its name is the owner's, never posted.
      [ -z "$SH_BOX" ] || { SH_NAME="Namespace Devbox $SH_BOX" SH_POST='Namespace Devbox'; } ;;
    *) SH_KIND=local SH_NAME='this machine' SH_POST='the build machine' ;;
  esac
  hostd
}
# SH_D of SH_DIR and the repo (hostrule()).
hostd() {
  local p
  # shellcheck disable=SC2088 # the rule's ~ is the box's, matched here as text, never this machine's home
  case $SH_DIR in '~') p='"$HOME"' ;; '~/'*) p='"$HOME"/'$(printf %q "${SH_DIR#??}") ;; *) p=$(printf %q "$SH_DIR") ;; esac
  SH_D="D=$p/$(printf %q "$REPO")"
}
# The facts (HOSTFACTS) of the rule's machine, with each <tool> named; fails as ssh or bash did.
hostfacts() { # <tool>...
  local s
  s="set -- $(printf '%q ' "$@"); $HOSTFACTS"
  if [ "$SH_KIND" = local ]; then bash -c "$s" < "$HERE/lib/slots.sh"; else hostssh "$s" 60 < "$HERE/lib/slots.sh"; fi
}
# The tools a .conveyor/test-machine.sh names on its `# needs: <tool> [<version>]` lines, one a line, jq and git left
# out (hostneeds() and hostcheck() name those apart): the script of <blob> (a commit's, hostsetup()), else the main
# checkout's.
hostneedtools() { # [blob]
  { if [ -n "${1:-}" ]; then git cat-file blob "$1"; else cat "$MAIN/.conveyor/test-machine.sh"; fi; } 2>/dev/null \
    | sed -n 's/^# needs:[[:space:]]*//p' | awk '{print $1}' | grep -E '^[A-Za-z0-9._+-]+$' | grep -vxE 'jq|git' | sort -u
}
# A box over ssh, or a devbox with its lease, fit to run the suite: it answers, with bash 5.1 or later, jq and git, and
# each <tool> given (after its setup, the tools its commit's .conveyor/test-machine.sh needs: hostsetup()). Sets SH_SLOTS
# to its test slots, or SH_WHY to why it is not fit, and fails.
hostneeds() { # [tool...]
  local f rc v via='' tools=("$@") miss
  [ "$SH_KIND" != ssh ] || via=' over ssh'
  SH_WHY=''; f=$(hostfacts jq git "${tools[@]}" 2>&1); rc=$?
  miss=$(for v in "${tools[@]}"; do grep -qxF "$(printf 'tool\t%s\tok' "$v")" <<<"$f" || echo "$v"; done | paste -sd ' ' -)
  if [ $rc = 255 ] && [ "$SH_KIND" = ssh ]; then SH_WHY="$SH_TARGET does not answer over ssh: $(grep . <<<"$f" | tail -n 1)"
  elif [ $rc = 124 ]; then SH_WHY="${SH_TARGET:-$SH_NAME} did not answer$via in 60 s"
  elif [ $rc != 0 ]; then SH_WHY="bash could not run there (exit $rc): $(grep . <<<"$f" | tail -n 1)"
  elif v=$(sed -n 's/^bash\t//p' <<<"$f") && ! { [[ $v =~ ^([0-9]+)\.([0-9]+)$ ]] && { [ "${BASH_REMATCH[1]}" -gt 5 ] || { [ "${BASH_REMATCH[1]}" = 5 ] && [ "${BASH_REMATCH[2]}" -ge 1 ]; }; }; }; then
    SH_WHY="it has bash ${v:-of no version}, not 5.1 or later"
  elif ! grep -qx $'tool\tjq\tok' <<<"$f"; then SH_WHY="jq is not installed there (slot_pool, and the suite's cases, read JSON with it)"
  elif ! grep -qx $'tool\tgit\tok' <<<"$f"; then SH_WHY="git is not installed there"
  elif [ -n "$miss" ]; then SH_WHY="$miss: not installed there (.conveyor/test-machine.sh needs it)"
  elif ! SH_SLOTS=$(sed -n 's/^slots\t\([1-9][0-9]*\)$/\1/p' <<<"$f") || [ -z "$SH_SLOTS" ]; then SH_WHY="its test slots cannot be read"; fi
  [ -z "$SH_WHY" ]
}
# The test slots of the rule's box (SH_SLOTS), read for `release-run atonce`: none to read for this machine's rule, and
# none for a devbox, which is leased only for a run.
hostslots() { # <command name>
  [ "$SH_KIND" != devbox ] || { echo "conveyor: $1: the test slots of $SH_NAME are read when a run leases it; nothing to print" >&2; return 1; }
  [ "$SH_KIND" = ssh ] || return 0
  hostneeds || { echo "conveyor: $1: the test slots of $SH_NAME cannot be read: $SH_WHY" >&2; return 1; }
}
# The step <step> begins: the one before it gets its seconds.
hoststep() { # <step>
  relrec --arg s "$1" --argjson d $((SECONDS - SH_T)) '.machine.secs[.machine.step] = $d | .machine.step = $s'; SH_T=$SECONDS SH_STEP=$1
}
# A devbox's lease given back (`devbox release --lease_id`), once: SH_LEASE is cleared, and the record keeps the lease it
# had. One that cannot be given back is said, and fails; the devbox stops itself when idle (idleStop). Nothing for a
# run with no lease.
hostrelease() { # <command name>
  local l=$SH_LEASE
  [ -n "$l" ] || return 0
  SH_LEASE=''
  timeout --kill-after=5 120 devbox release --lease_id "$l" > /dev/null 2>&1 < /dev/null \
    || { echo "conveyor: $1: the devbox lease $l could not be given back; it stops itself when it is idle" >&2; return 1; }
}
# The login to Namespace and the devbox command, on this machine. Sets SH_WHY to why not, and fails.
hostlogin() {
  SH_WHY=''
  command -v devbox > /dev/null || { SH_WHY='the devbox command is not installed on this machine'; return 1; }
  timeout --kill-after=5 60 devbox auth check-login > /dev/null 2>&1 < /dev/null || { SH_WHY='Not logged in to Namespace'; return 1; }
}
# The account's devboxes: their names, a JSON array, from `devbox list -o json`, in SH_BOXES (null when they cannot be read:
# SH_WHY says why, and it fails).
hostboxes() {
  SH_BOXES=$(timeout --kill-after=5 60 devbox list -o json 2> /dev/null < /dev/null | jq -c '[.[] | .name | strings]' 2> /dev/null) && [ -n "$SH_BOXES" ] \
    || { SH_BOXES=null SH_WHY="the account's devboxes could not be listed with devbox list"; return 1; }
}
# A devbox leased: `devbox acquire <tag>` with the size and the idle stop, which prints the box's name and the lease id
# last, in SH_LEASE; its whole output in SH_ACQ. Sets SH_WHY to why not, and fails.
hostlease() { # <seconds>
  local out
  out=$(timeout --kill-after=5 "$1" devbox acquire "$SH_TAG" --size "$SH_SIZE" --auto_stop_idle_timeout "$SH_IDLE" 2>&1 < /dev/null) \
    || { SH_WHY="a devbox could not be acquired: $(grep . <<<"$out" | tail -n 1)"; return 1; }
  SH_ACQ=$out
  out=$(grep . <<<"$out" | tail -n 1)
  [[ $out =~ ^[A-Za-z0-9][A-Za-z0-9._:-]*$ ]] || { SH_WHY="devbox acquire did not print a lease id: ${out:0:200}"; return 1; }
  SH_LEASE=$out
}
# The devbox of the run: a box named in the rule is started (`devbox exec <box> -- true`) and kept in the record; else
# one is leased (hostlease()) and its lease kept in the record, which `release-run stop` reads (hoststop()).
# Sets SH_WHY to why not, and fails.
hostacquire() {
  local out
  hostlogin || return 1
  if [ -n "$SH_BOX" ]; then
    out=$(timeout --kill-after=5 300 devbox exec "$SH_BOX" -- true 2>&1 < /dev/null) \
      || { SH_WHY="the devbox $SH_BOX could not be started: $(grep . <<<"$out" | tail -n 1)"; return 1; }
    return 0
  fi
  hostlease 300 || return 1
  relrec --arg l "$SH_LEASE" '.machine.lease = $l'
}
# The step under way failed: the run ends "not started" with <reason>, which is printed, so the record's reasons hold it.
# A devbox's lease is given back.
hostfail() { # <command name> <reason>
  hostrelease "$1" || :
  relrec --arg r "$2" --argjson d $((SECONDS - SH_T)) '.machine.secs[.machine.step] = $d | .machine.reason = $r | .state = "not started"'
  echo "conveyor: $1: the suite was not started on $SH_NAME: $2; nothing run" >&2
}
# start: the rule read and kept in the record, a devbox leased (hostacquire()), and a box over ssh or a devbox checked
# (hostneeds()).
hoststart() { # <command name>
  hostrule "$1" || return 1
  SH_T=$SECONDS SH_STEP=start
  relrec --arg k "$SH_KIND" --arg n "$SH_NAME" --arg t "$SH_TARGET" --arg d "$SH_DIR" --arg b "$SH_BOX" \
    '.machine = {kind: $k, name: $n, target: (if $k == "ssh" then $t else null end), dir: (if $k == "ssh" then $d else null end), lease: null, step: "start", secs: {}, reason: null} + (if $b != "" then {box: $b} else {} end)'
  [ "$SH_KIND" != devbox ] || hostacquire || { hostfail "$1" "$SH_WHY"; return 1; }
  [ "$SH_KIND" = local ] || hostneeds || { hostfail "$1" "$SH_WHY"; return 1; }
}
# setup: the commit's .conveyor/test-machine.sh, sent on ssh's input, run on the box when it last ran another blob. The box
# keeps the time of that run in setup.at beside setup.blob (a box set up before that file, the mtime of setup.blob, or now
# where date cannot read it), and says it on its last line; a devbox's rule keeps it (setupAt, hostsetupat()), whether the
# script ran in this call or an earlier one. Then the box has each tool the script's `# needs:` lines name, or the run
# ends not started (hostneeds()). Bug (R405): only jq and git were checked, so a box whose script had run before
# (setup.blob current) and that lacked a needed tool started the run, which failed in the suite. The tools are the
# commit's script's, read after it ran: the main checkout's script, read at the start, refused a new box the script
# would set up, and named the tools of another commit than the one tested.
hostsetup() { # <command name> <commit>
  local h out t tools=()
  hoststep setup
  [ "$SH_KIND" != local ] && h=$(git rev-parse -q --verify "$2:.conveyor/test-machine.sh" 2>/dev/null) || return 0
  out=$(git cat-file blob "$h" | hostssh "$SH_D"'; mkdir -p "$D" && cd "$D" && { [ "$(cat setup.blob 2> /dev/null)" = '"$h"' ] || { bash -s && echo '"$h"' > setup.blob && date -u +%Y-%m-%dT%H:%M:%SZ > setup.at; }; } \
    && { [ -s setup.at ] || { date -u -r setup.blob +%Y-%m-%dT%H:%M:%SZ 2> /dev/null || date -u +%Y-%m-%dT%H:%M:%SZ; } > setup.at; } && echo "conveyor-setup-at $(cat setup.at)"' 2>&1) \
    || { hostfail "$1" "its .conveyor/test-machine.sh failed: $(grep . <<<"$out" | tail -n 5 | paste -sd ';' -)"; return 1; }
  if [ "$SH_KIND" = devbox ]; then
    t=$(grep '^conveyor-setup-at ' <<<"$out" | tail -n 1); t=${t#conveyor-setup-at }
    [[ $t =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z$ ]] && locked hostsetupat "$t" || echo "conveyor: $1: the devbox's set-up time could not be kept in the control record" >&2
  fi
  mapfile -t tools < <(hostneedtools "$h")
  [ ${#tools[@]} = 0 ] || hostneeds "${tools[@]}" || { hostfail "$1" "$SH_WHY"; return 1; }
}
# Under the lock: the devbox rule keeps <time> as when the box's script last ran (setupAt, the Board's Box line), when the rule is still a devbox.
hostsetupat() { # <time>
  local c new; c=$(ctl) || return 1
  new=$(jq -c --arg t "$1" 'if .suiteMachine.kind == "devbox" then .suiteMachine.setupAt = $t else . end' <<<"$c") && ctlput "$c" "$new"
}
# checkout: the worktree <worktree> of <commit> here; on a box over ssh, the commit's bundle checked out there (a run
# of it still going there stopped first) and the pack's worktree.setup run in it.
hostcheckout() { # <command name> <worktree> <commit>
  local out s=''
  hoststep checkout
  out=$({ git worktree remove --force "$2" 2>/dev/null; rm -rf "$2" "$2".*; git worktree prune
    git worktree add -q --detach "$2" "$3" && deps "$2"; } 2>&1 < /dev/null) || {
    git worktree remove --force "$2" 2>/dev/null; hostfail "$1" "the worktree of ${3:0:12} could not be made: ${out:0:600}"; return 1; }
  [ "$SH_KIND" != local ] || return 0
  packget worktree.setup s || { hostfail "$1" "the pack's worktree.setup cannot be read"; return 1; }
  [ -z "$s" ] || s="&& cd wt && bash -c $(hostq "$s") < /dev/null"
  out=$(git -C "$2" bundle create - HEAD 2>/dev/null | hostssh "$SH_D"'; mkdir -p "$D" && cd "$D" && { p=$(cat wt.pid 2> /dev/null) && kill -TERM -- -"$p" 2> /dev/null; rm -f wt.pid
    rm -rf wt && cat > wt.bundle && git init -q wt && git -C wt fetch -q "$D/wt.bundle" HEAD && git -C wt checkout -q --detach FETCH_HEAD; } && rm -f wt.bundle
    [ "$(git -C wt rev-parse HEAD 2> /dev/null)" = '"$3"' ] '"$s" 2>&1) \
    || { hostfail "$1" "the commit ${3:0:12} could not be checked out there: $(grep . <<<"$out" | tail -n 5 | paste -sd ';' -)"; return 1; }
}
# run: tests() here; on a box over ssh or a devbox, the pack's <field> command there, in its checkout, as tests() runs it: with
# alone, the list <worktree>.rerun names (fullalone()). Its exit is the command's; 1 when the box stops answering for
# six polls in a row (each poll ended at HOSTPOLL), which stops the run there when the box answers that, and 124 when the run ends past the time limit of a run here
# (testTimeout: HOSTRUN), or is still going a poll's time (HOSTPOLL) past it, which stops it there; its output says which.
hosttests() { # <worktree> <field> [alone]
  [ "$SH_STEP" = run ] || hoststep run
  [ "$SH_KIND" != local ] || { tests "$@"; return; }
  local cmd e i=0 rc at pr='' was='' now out t0 lim=${TEST_TIMEOUT:-} via=''
  [[ $lim =~ ^[1-9][0-9]*$ ]] || lim=3600
  [ "$SH_KIND" != ssh ] || via=' over ssh'
  packget "$2" cmd || return 1
  rm -rf "$1.test" "$1.testlog" "$1.rc" "$1.live" "$1.send" "$1.got"; mkdir -p "$1.send" "$1.testlog" "$1.got" && : > "$1.test" || return 1
  e="CONVEYOR_SUITE_MODE=$(hostq "${CONVEYOR_SUITE_MODE:-}") CONVEYOR_SUITE_AT_ONCE=$(hostq "${CONVEYOR_SUITE_AT_ONCE:-}") CONVEYOR_TEST_LOG=\"\$D/wt.testlog\""
  [ -z "${CONVEYOR_SUITE_FILES:-}" ] || { cp "$CONVEYOR_SUITE_FILES" "$1.send/files" && e+=' CONVEYOR_SUITE_FILES="$D/in/files"'; } || return 1
  [ "${3:-}" != alone ] || { cp "$1.rerun" "$1.send/rerun" && e+=' CONVEYOR_TEST_RERUN="$D/in/rerun"'; } || return 1
  [ ! -s "${CONVEYOR_SUITE_RECORD:-}" ] || { cp "$CONVEYOR_SUITE_RECORD" "$1.send/record" && e+=' CONVEYOR_SUITE_RECORD="$D/in/record"'; } || return 1
  # Two commands: the files sent on the first's input, then the run started (on a devbox, detached with `exec -d`, which
  # takes no input).
  if ! out=$({ tar -C "$1.send" -cf - . | hostssh "$SH_D"'; cd "$D/wt" && cd .. && rm -rf wt.test wt.testlog wt.rc wt.pid in && mkdir wt.testlog in && : > wt.test && tar -xf - -C in' 60 \
    && hostssh "$SH_D"'; cd "$D/wt" && export '"$e"' || exit 1
      S=$(command -v setsid || :); nohup $S bash -c '"$(hostq "$HOSTRUN")"' _ '"$(hostq "$cmd") $(hostq "$lim") $(hostq "$SH_NAME")"' > /dev/null 2>&1 < /dev/null & echo $! > ../wt.pid' 60 detach < /dev/null; } 2>&1); then
    printf 'conveyor: the suite could not be started on %s: %s\n' "$SH_NAME" "$(grep . <<<"$out" | tail -n 1)" > "$1.test"; return 1
  fi
  at=$(date -u +%FT%TZ) t0=$SECONDS
  # Each poll waits there up to 10 s for the run's exit, then sends its output, log folder and exit (once there).
  until [ -s "$1.rc" ]; do
    rm -rf "$1.got"/*
    if hostssh "$SH_D"'; cd "$D" && p=$(cat wt.pid 2> /dev/null); i=0
        while [ ! -s wt.rc ] && [ $i -lt 10 ]; do
          kill -0 "$p" 2> /dev/null || { [ -s wt.rc ] || { echo "conveyor: the suite'\''s process ended there with no exit code" >> wt.test; echo 255 > wt.rc; }; break; }
          sleep 1; i=$((i + 1)); done
        tar -cf - wt.test wt.testlog $([ ! -s wt.rc ] || echo wt.rc)' "$HOSTPOLL" < /dev/null 2>/dev/null | tar -xf - -C "$1.got" 2>/dev/null && [ -f "$1.got/wt.test" ]; then
      i=0; mv -f "$1.got/wt.test" "$1.test"; cp -pR "$1.got/wt.testlog/." "$1.testlog/" 2>/dev/null; [ ! -f "$1.got/wt.rc" ] || mv -f "$1.got/wt.rc" "$1.rc"
    else i=$((i + 1)); fi
    # The live record: its progress is when the output or the log folder last changed.
    now=$(date -u +%FT%TZ); [ "$was" = "$(cksum < "$1.test" 2>/dev/null)$(find "$1.testlog" 2>/dev/null | wc -l)" ] || { pr=$now; was=$(cksum < "$1.test" 2>/dev/null)$(find "$1.testlog" 2>/dev/null | wc -l); }
    jq -cn --arg at "$at" --arg l "$now" --arg p "$pr" '{step: "test", at: $at, last: $l, progress: $p}' > "$1.live.tmp" && mv -f "$1.live.tmp" "$1.live"
    # Given up on, the run there is stopped too, when the box answers that: else it would run on, unseen.
    [ $i -lt 6 ] || {
      out="it $(hostkill "$via")"
      printf 'conveyor: %s stopped answering%s while the suite ran there; %s\n' "$SH_NAME" "$via" "$out" >> "$1.test"; rm -rf "$1.send" "$1.got"; return 1; }
    [ -s "$1.rc" ] || [ $((SECONDS - t0)) -lt $((lim + HOSTPOLL)) ] || {
      out=$(hostkill "$via")
      printf 'conveyor: the suite ran past its time limit, %s s (testTimeout), on %s and %s\n' "$lim" "$SH_NAME" "$out" >> "$1.test"; rm -rf "$1.send" "$1.got"; return 124; }
  done
  rc=$(<"$1.rc"); rm -rf "$1.rc" "$1.send" "$1.got"
  [[ $rc =~ ^[0-9]+$ ]] || rc=1
  return "$rc"
}
# results: the run's files cleared on a box over ssh, a devbox's lease given back (its results came back with the last
# poll), and the steps done.
hostfinish() { # <command name>
  hoststep results
  [ "$SH_KIND" != ssh ] || hostssh "$SH_D"'; rm -rf "$D/wt.pid" "$D/in"' 30 < /dev/null > /dev/null 2>&1 || :
  hostrelease "$1" || :
  hoststep 'done'
}
# `release-run stop`: the run on the box over ssh or the devbox that the record names, stopped there (HOSTKILL), when the
# record is still the stopped run's (its <pid> and <since>, read in the same read as its machine) and its machine has
# not reached done; a devbox's lease is given back too. A record of another run (one started once the stopped run let
# the release lock go), or one that cannot be read, is left alone: its machine is that run's, and its suite there is not
# stopped (exit 2).
hoststop() { # <pid> <since>
  local m via='' out
  # One read: nothing when the record is not the run's, null when the run has no suite's run on a box to stop.
  m=$(jq -c --argjson p "$1" --arg s "$2" 'select(.pid == $p and .since == $s) | ('"$HOSTLIVE"') // null' "$RELRUN" 2>/dev/null) && [ -n "$m" ] || return 2
  [ "$m" != null ] || return 0
  SH_KIND=$(jq -r .kind <<<"$m") SH_TARGET=$(jq -r '.target // ""' <<<"$m") SH_DIR=$(jq -r '.dir // "~/conveyor-suite"' <<<"$m") SH_LEASE=$(jq -r '.lease // ""' <<<"$m") SH_BOX=$(jq -r '.box // ""' <<<"$m") && hostd
  [ "$SH_KIND" != ssh ] || via=' over ssh'
  out=$(hostkill "$via") || echo "conveyor: release-run stop: the suite's run on $(jq -r .name <<<"$m") $out" >&2
  hostrelease "release-run stop"
}
# The Devbox need of a check, added to hostcheck()'s needs (n), and the account's devbox names in SH_BOXES (a JSON array, null
# when the list cannot be read). A box named in the rule must be in that list (hostboxes()). With none named, the one way to know
# whether the account can give one is to ask for it: a box is leased under the tag (an existing one is reused, else a new one
# is made, which the list before and after tells) and given back at once; one refused for the account's limit says so, with the
# fix (a box of the account, named in the rule, or one removed). With <no-create> (a member's check on the Board) none is asked for.
hostboxneed() { # [no-create]
  local ok=false msg='' was='' a
  hostboxes && was=$SH_BOXES || msg=$SH_WHY
  if [ -n "$SH_BOX" ]; then
    if [ -z "$was" ]; then :
    elif jq -e --arg b "$SH_BOX" 'index($b) != null' <<<"$was" > /dev/null; then ok=true msg="the box $SH_BOX is started for the run"
    else msg="no devbox named $SH_BOX is in this account; it has: $(jq -r 'join(", ")' <<<"$was"). Pick one with control suite-machine devbox --box <name>"; fi
  elif [ "${1:-}" = no-create ]; then
    ok=true msg="the run reuses the box tagged $SH_TAG, or creates one; this check does not ask for one"
  elif hostlease 100; then
    ok=true msg="the run reuses the box tagged $SH_TAG"
    # Created: the box leased is one the list did not have before. Its name is the one acquire resolves: the last word of
    # the line before the lease id, the marks around it left out. A box another project made meanwhile is new to the list
    # too, but is not that name, even when its name is a word of acquire's other lines.
    a=$(grep . <<<"$SH_ACQ" | tail -n 2 | head -n 1); a=${a##*[[:space:]]}
    [[ $a =~ ^[^A-Za-z0-9]*(.*[A-Za-z0-9])[^A-Za-z0-9]*$ ]] && a=${BASH_REMATCH[1]} || a=''
    if [ -n "$was" ] && [ -n "$a" ] && hostboxes && jq -e --argjson w "$was" --arg a "$a" '. - $w | index($a) != null' <<<"$SH_BOXES" > /dev/null; then
      msg="no box tagged $SH_TAG was found, so a new one was created for the run to reuse"; fi
    hostrelease suite-machine || msg="$msg (the lease taken to try it could not be given back; it stops itself when idle)"
  else
    msg=$SH_WHY
    case $SH_WHY in *[Ll]imit*) msg="$SH_WHY. No box tagged $SH_TAG was found and the account is at its devbox limit: pick an existing devbox with control suite-machine devbox --box <name>, or remove one" ;; *) ;; esac
  fi
  n+=("$(jq -cn --argjson ok $ok --arg d "$msg" '{need: "Devbox", ok: $ok, detail: $d}')")
}
# `conveyor.sh suite-machine check [--json]`: one line a need of the rule's machine, ok or missing: ssh reach (a box
# over ssh), bash 5.1 or later, jq, git and each tool the main checkout's .conveyor/test-machine.sh names on a
# `# needs: <tool> [<version>]` line (the tool is the command; the version is for people, not checked), then its CPU count and test slots (slot_pool's, here or on the box: HOSTFACTS). With
# json: {kind, name, ok, needs: [{need, ok, detail}], cpus, slots, boxes (a devbox's: the account's devbox names, else null)}. Exit 0: every need ok; 1: one is missing. For a
# devbox, the needs are the Namespace login (hostlogin()) and the box (hostboxneed()), and cpus and slots are null: it is leased only for a run.
hostcheck() { # [json [no-create]]
  local tools=() f rc v='' n=() ok sl=''
  SH_BOXES=null
  hostrule suite-machine || return 1
  if [ "$SH_KIND" = devbox ]; then
    # A devbox is leased only for a run: its bash, tools and test slots cannot be read without one, its login can.
    hostlogin && ok=true || ok=false
    n+=("$(jq -cn --argjson ok $ok --arg w "$SH_WHY" '{need: "Namespace login", ok: $ok, detail: (if $ok then "logged in" else $w end)}')")
    [ "$ok" = false ] || hostboxneed "${2:-}"
  else
    mapfile -t tools < <(hostneedtools)
    f=$(hostfacts jq git "${tools[@]}" 2>&1); rc=$?
    [ "$SH_KIND" = local ] || n+=("$(jq -cn --arg t "$SH_TARGET" --argjson ok "$([ $rc = 255 ] && echo false || echo true)" --arg w "$([ $rc != 255 ] || grep . <<<"$f" | tail -n 1)" \
      '{need: "ssh", ok: $ok, detail: (if $ok then "\($t) answers" else "\($t) does not answer: \($w)" end)}')")
    v=$(sed -n 's/^bash\t//p' <<<"$f")
    ok=false; [[ $v =~ ^([0-9]+)\.([0-9]+)$ ]] && { [ "${BASH_REMATCH[1]}" -gt 5 ] || { [ "${BASH_REMATCH[1]}" = 5 ] && [ "${BASH_REMATCH[2]}" -ge 1 ]; }; } && ok=true
    n+=("$(jq -cn --argjson ok $ok --arg v "$v" '{need: "bash 5.1+", ok: $ok, detail: (if $v == "" then "no bash answered" else "bash \($v)" end)}')")
    for v in jq git "${tools[@]}"; do
      n+=("$(jq -cn --arg t "$v" --argjson ok "$(grep -qxF "$(printf 'tool\t%s\tok' "$v")" <<<"$f" && echo true || echo false)" --argjson m "$(printf '%s\n' "${tools[@]}" | grep -qxF -- "$v" && echo true || echo false)" \
        '{need: $t, ok: $ok, detail: (if $ok then "installed" else "not installed" end + if $m then " (.conveyor/test-machine.sh)" else "" end)}')")
    done
    v=$(sed -n 's/^cpus\t\([1-9][0-9]*\)$/\1/p' <<<"$f")
    sl=$(sed -n 's/^slots\t\([1-9][0-9]*\)$/\1/p' <<<"$f")
    n+=("$(jq -cn --arg c "$v" --arg s "$sl" '{need: "test slots", ok: ($c != "" and $s != ""), detail: (if $c == "" then "its CPU count cannot be read" elif $s == "" then "\($c) CPUs, its test slots cannot be read" else "\($c) CPUs, \($s) test slots" end)}')")
  fi
  f=$(printf '%s\n' "${n[@]}" | jq -cs --arg k "$SH_KIND" --arg nm "$SH_NAME" --arg c "$v" --arg s "$sl" --argjson b "$SH_BOXES" \
    '{kind: $k, name: $nm, ok: all(.[]; .ok), needs: ., cpus: ($c | tonumber? // null), slots: ($s | tonumber? // null), boxes: $b}') || return 1
  if [ "${1:-}" = json ]; then printf '%s\n' "$f"
  else jq -r '"conveyor: suite-machine: the suite runs on \(.name)", (.needs[] | "\(if .ok then "ok" else "missing" end): \(.need): \(.detail)")' <<<"$f"; fi
  jq -e .ok <<<"$f" > /dev/null
}
