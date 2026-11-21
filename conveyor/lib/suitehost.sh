# SPDX-License-Identifier: Apache-2.0
# The machine a release's whole suite runs on (relsuite(), commands/release-prep.sh; docs/releases.md, Where the suite
# runs). The control record's suiteMachine is the rule: {kind: "local"}, this machine (the default, also when the record
# has none), or {kind: "ssh", target: <user@host>, dir: <folder there>}, a Linux box over ssh, set with `conveyor.sh
# control suite-machine`. `release-run ... --machine local` runs one run here whatever the rule says (releasego() is
# given CONVEYOR_RELEASE_MACHINE=local). A run goes through its steps in order, each named in the run's record as it
# begins (machine.step, then done) with the seconds of each step that ended (machine.secs):
# - start: local, nothing. ssh: the box answers over ssh with no password asked, has bash 5.1 or later and git, and its
#   test slots are read (HOSTFACTS): the most files a parallel suite runs at once there (relatonce()).
# - setup: local, nothing. ssh: the tested commit's .conveyor/test-machine.sh runs there when its blob is not the one the
#   box last ran (<dir>/<repo>/setup.blob); with no such file it is skipped.
# - checkout: the worktree of the commit here ($CARDS/release/wt, deps()), which the changed-tests selection and the
#   records read. ssh: also a git bundle of the commit, sent on ssh's input and checked out in <dir>/<repo>/wt (the box
#   needs no clone access and is given no GitHub token), then the pack's worktree.setup run there.
# - run: local, tests() on this machine's test slots. ssh: test.full started there with nohup (each run alone of a
#   failed case too, fullalone()), told the run's CONVEYOR_SUITE_* and its log folder; a poller copies its output and
#   log folder back to <worktree>.test and <worktree>.testlog at least every 10 s and writes <worktree>.live, so the
#   records, the snapshot, the reruns (suitereuse()) and the flaky rule read the same files as of a run here. A run
#   there takes no test slot of this machine; one that ends past a run here's time limit (testTimeout) timed out, and
#   one still going a poll's time past it is stopped there.
# - results: the box's run files are cleared.
# A start, setup or checkout that fails ends the run "not started": its reason goes in machine.reason and the record's
# reasons, nothing runs, and the suite never moves to another machine by itself. `release-run stop` stops the run
# there too (hoststop()). The record's machine is {kind, name (for people: "this machine", or the ssh host), target
# and dir (ssh's, else null), step, secs, reason}. Sourced by commands/release-prep.sh and commands/suite-machine.sh.
SH_KIND=local SH_NAME='this machine' SH_POST='the build machine' SH_TARGET='' SH_DIR='' SH_D='' SH_SLOTS='' SH_STEP='' SH_T=0 SH_WHY=''
# What every check of a box prints, one fact a line: its bash version, each tool named (ok or missing), its CPUs and
# its test slots: slot_pool's there, of lib/slots.sh sent on ssh's input (hostfacts()), so its host file's testSlots
# and its cores cap them as the suite's runner there finds them (.conveyor/test-full.sh), never its CPU count alone.
HOSTFACTS='printf "bash\t%s\n" "${BASH_VERSINFO[0]}.${BASH_VERSINFO[1]}"
for t; do printf "tool\t%s\t%s\n" "$t" "$(command -v "$t" > /dev/null && echo ok || echo missing)"; done
printf "cpus\t%s\n" "$(nproc 2> /dev/null || getconf _NPROCESSORS_ONLN 2> /dev/null || echo 0)"
printf "slots\t%s\n" "$(. /dev/stdin > /dev/null 2>&1 && slot_pool > /dev/null 2>&1 && echo "$SLOT_N")"'
# The suite's run on the box (hosttests()), given its <command>, <time limit> and the box's <name>: its exit in wt.rc,
# timed by the box's own clock, which starts before this machine's: a run that ends past the limit, even with 0, has
# 124, the exit of a run here that timed out, and its output says so.
HOSTRUN='bash -c "$1" > ../wt.test 2>&1 < /dev/null; r=$?
[ "$SECONDS" -lt "$2" ] || { r=124; echo "conveyor: the suite ran past its time limit, $2 s (testTimeout), on $3" >> ../wt.test; }
echo "$r" > ../wt.rc'
# The suite's run on the box stopped: its process group, which setsid made, else its process.
HOSTKILL='p=$(cat "$D/wt.pid" 2> /dev/null) && { kill -TERM -- -"$p" 2> /dev/null || kill -TERM "$p" 2> /dev/null; }; rm -f "$D/wt.pid"'
# The seconds one poll of the run on the box may take (hosttests()): its 10 s wait there, then the copy of its output.
HOSTPOLL=60
# <text> in single quotes, as any POSIX shell reads it: the box's login shell is not always bash.
hostq() { printf "'%s'" "${1//\'/\'\\\'\'}"; }
# <script> run by bash on the rule's box, its input ssh's: no password is asked (BatchMode), at most 20 s to connect,
# and a link that stops answering ends it in 30 s (ServerAlive). With <seconds>, ssh is ended then (exit 124), so a
# box that answers ssh but not the script (a stalled poll) holds no step for longer.
hostssh() { # <script> [seconds]
  local t=(); [ -z "${2:-}" ] || t=(timeout --kill-after=5 "$2")
  "${t[@]}" ssh -o BatchMode=yes -o ConnectTimeout=20 -o ServerAliveInterval=10 -o ServerAliveCountMax=3 -- "$SH_TARGET" "bash -c $(hostq "$1")"
}
# The rule of this run, in SH_KIND, SH_NAME, SH_POST (the name a commit status gives it: a host's name is never
# posted, as the status is public), SH_TARGET, SH_DIR and SH_D (the shell line that sets D, the run's folder on the
# box: <dir>/<repo>, a ~ at the start of dir read as the box's $HOME).
hostrule() { # <command name>
  local r
  if [ "${CONVEYOR_RELEASE_MACHINE:-}" = local ]; then r='{"kind":"local"}'
  else r=$(ctl | jq -ce '.suiteMachine | objects') || { echo "conveyor: $1: the control record's suiteMachine cannot be read; nothing run" >&2; return 1; }; fi
  SH_KIND=$(jq -r .kind <<<"$r") SH_TARGET=$(jq -r '.target // ""' <<<"$r") SH_DIR=$(jq -r '.dir // ""' <<<"$r")
  # shellcheck disable=SC2034 # SH_POST is read by relsuite(), commands/release-prep.sh
  if [ "$SH_KIND" = ssh ]; then SH_NAME=${SH_TARGET#*@} SH_POST='a Linux box over ssh'; else SH_KIND=local SH_NAME='this machine' SH_POST='the build machine'; fi
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
  if [ "$SH_KIND" = ssh ]; then hostssh "$s" 60 < "$HERE/lib/slots.sh"; else bash -c "$s" < "$HERE/lib/slots.sh"; fi
}
# A box over ssh fit to run the suite: it answers, with bash 5.1 or later and git. Sets SH_SLOTS to its test slots, or
# SH_WHY to why it is not fit, and fails.
hostneeds() {
  local f rc v
  SH_WHY=''; f=$(hostfacts git 2>&1); rc=$?
  if [ $rc = 255 ]; then SH_WHY="$SH_TARGET does not answer over ssh: $(grep . <<<"$f" | tail -n 1)"
  elif [ $rc = 124 ]; then SH_WHY="$SH_TARGET did not answer over ssh in 60 s"
  elif [ $rc != 0 ]; then SH_WHY="bash could not run there (exit $rc): $(grep . <<<"$f" | tail -n 1)"
  elif v=$(sed -n 's/^bash\t//p' <<<"$f") && ! { [[ $v =~ ^([0-9]+)\.([0-9]+)$ ]] && { [ "${BASH_REMATCH[1]}" -gt 5 ] || { [ "${BASH_REMATCH[1]}" = 5 ] && [ "${BASH_REMATCH[2]}" -ge 1 ]; }; }; }; then
    SH_WHY="it has bash ${v:-of no version}, not 5.1 or later"
  elif ! grep -qx $'tool\tgit\tok' <<<"$f"; then SH_WHY="git is not installed there"
  elif ! SH_SLOTS=$(sed -n 's/^slots\t\([1-9][0-9]*\)$/\1/p' <<<"$f") || [ -z "$SH_SLOTS" ]; then SH_WHY="its test slots cannot be read"; fi
  [ -z "$SH_WHY" ]
}
# The test slots of the rule's box (SH_SLOTS), read for `release-run atonce`: none to read for this machine's rule.
hostslots() { # <command name>
  [ "$SH_KIND" = ssh ] || return 0
  hostneeds || { echo "conveyor: $1: the test slots of $SH_NAME cannot be read: $SH_WHY" >&2; return 1; }
}
# The step <step> begins: the one before it gets its seconds.
hoststep() { # <step>
  relrec --arg s "$1" --argjson d $((SECONDS - SH_T)) '.machine.secs[.machine.step] = $d | .machine.step = $s'; SH_T=$SECONDS SH_STEP=$1
}
# The step under way failed: the run ends "not started" with <reason>, which is printed, so the record's reasons hold it.
hostfail() { # <command name> <reason>
  relrec --arg r "$2" --argjson d $((SECONDS - SH_T)) '.machine.secs[.machine.step] = $d | .machine.reason = $r | .state = "not started"'
  echo "conveyor: $1: the suite was not started on $SH_NAME: $2; nothing run" >&2
}
# start: the rule read and kept in the record, and a box over ssh checked (hostneeds()).
hoststart() { # <command name>
  hostrule "$1" || return 1
  SH_T=$SECONDS SH_STEP=start
  relrec --arg k "$SH_KIND" --arg n "$SH_NAME" --arg t "$SH_TARGET" --arg d "$SH_DIR" \
    '.machine = {kind: $k, name: $n, target: (if $k == "ssh" then $t else null end), dir: (if $k == "ssh" then $d else null end), step: "start", secs: {}, reason: null}'
  [ "$SH_KIND" = local ] || hostneeds || { hostfail "$1" "$SH_WHY"; return 1; }
}
# setup: the commit's .conveyor/test-machine.sh, sent on ssh's input, run on the box when it last ran another blob.
hostsetup() { # <command name> <commit>
  local h out
  hoststep setup
  [ "$SH_KIND" = ssh ] && h=$(git rev-parse -q --verify "$2:.conveyor/test-machine.sh" 2>/dev/null) || return 0
  out=$(git cat-file blob "$h" | hostssh "$SH_D"'; mkdir -p "$D" && cd "$D" && { [ "$(cat setup.blob 2> /dev/null)" = '"$h"' ] || { bash -s && echo '"$h"' > setup.blob; }; }' 2>&1) \
    || { hostfail "$1" "its .conveyor/test-machine.sh failed: $(grep . <<<"$out" | tail -n 5 | paste -sd ';' -)"; return 1; }
}
# checkout: the worktree <worktree> of <commit> here; on a box over ssh, the commit's bundle checked out there (a run
# of it still going there stopped first) and the pack's worktree.setup run in it.
hostcheckout() { # <command name> <worktree> <commit>
  local out s=''
  hoststep checkout
  out=$({ git worktree remove --force "$2" 2>/dev/null; rm -rf "$2" "$2".*; git worktree prune
    git worktree add -q --detach "$2" "$3" && deps "$2"; } 2>&1 < /dev/null) || {
    git worktree remove --force "$2" 2>/dev/null; hostfail "$1" "the worktree of ${3:0:12} could not be made: ${out:0:600}"; return 1; }
  [ "$SH_KIND" = ssh ] || return 0
  packget worktree.setup s || { hostfail "$1" "the pack's worktree.setup cannot be read"; return 1; }
  [ -z "$s" ] || s="&& cd wt && bash -c $(hostq "$s") < /dev/null"
  out=$(git -C "$2" bundle create - HEAD 2>/dev/null | hostssh "$SH_D"'; mkdir -p "$D" && cd "$D" && { p=$(cat wt.pid 2> /dev/null) && kill -TERM -- -"$p" 2> /dev/null; rm -f wt.pid
    rm -rf wt && cat > wt.bundle && git init -q wt && git -C wt fetch -q "$D/wt.bundle" HEAD && git -C wt checkout -q --detach FETCH_HEAD; } && rm -f wt.bundle
    [ "$(git -C wt rev-parse HEAD 2> /dev/null)" = '"$3"' ] '"$s" 2>&1) \
    || { hostfail "$1" "the commit ${3:0:12} could not be checked out there: $(grep . <<<"$out" | tail -n 5 | paste -sd ';' -)"; return 1; }
}
# run: tests() here; on a box over ssh, the pack's <field> command there, in its checkout, as tests() runs it: with
# alone, the list <worktree>.rerun names (fullalone()). Its exit is the command's; 1 when the box stops answering for
# six polls in a row (each poll ended at HOSTPOLL), and 124 when the run ends past the time limit of a run here
# (testTimeout: HOSTRUN), or is still going a poll's time (HOSTPOLL) past it, which stops it there; its output says which.
hosttests() { # <worktree> <field> [alone]
  [ "$SH_STEP" = run ] || hoststep run
  [ "$SH_KIND" = ssh ] || { tests "$@"; return; }
  local cmd e i=0 rc at pr='' was='' now out t0 lim=${TEST_TIMEOUT:-}
  [[ $lim =~ ^[1-9][0-9]*$ ]] || lim=3600
  packget "$2" cmd || return 1
  rm -rf "$1.test" "$1.testlog" "$1.rc" "$1.live" "$1.send" "$1.got"; mkdir -p "$1.send" "$1.testlog" "$1.got" && : > "$1.test" || return 1
  e="CONVEYOR_SUITE_MODE=$(hostq "${CONVEYOR_SUITE_MODE:-}") CONVEYOR_SUITE_AT_ONCE=$(hostq "${CONVEYOR_SUITE_AT_ONCE:-}") CONVEYOR_TEST_LOG=\"\$D/wt.testlog\""
  [ -z "${CONVEYOR_SUITE_FILES:-}" ] || { cp "$CONVEYOR_SUITE_FILES" "$1.send/files" && e+=' CONVEYOR_SUITE_FILES="$D/in/files"'; } || return 1
  [ "${3:-}" != alone ] || { cp "$1.rerun" "$1.send/rerun" && e+=' CONVEYOR_TEST_RERUN="$D/in/rerun"'; } || return 1
  [ ! -s "${CONVEYOR_SUITE_RECORD:-}" ] || { cp "$CONVEYOR_SUITE_RECORD" "$1.send/record" && e+=' CONVEYOR_SUITE_RECORD="$D/in/record"'; } || return 1
  if ! out=$(tar -C "$1.send" -cf - . | hostssh "$SH_D"'; cd "$D/wt" && cd .. && rm -rf wt.test wt.testlog wt.rc wt.pid in && mkdir wt.testlog in && : > wt.test && tar -xf - -C in && cd wt && export '"$e"' || exit 1
      S=$(command -v setsid || :); nohup $S bash -c '"$(hostq "$HOSTRUN")"' _ '"$(hostq "$cmd") $(hostq "$lim") $(hostq "$SH_NAME")"' > /dev/null 2>&1 < /dev/null & echo $! > ../wt.pid' 60 2>&1); then
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
    [ $i -lt 6 ] || { printf 'conveyor: %s stopped answering over ssh while the suite ran there\n' "$SH_NAME" >> "$1.test"; rm -rf "$1.send" "$1.got"; return 1; }
    [ -s "$1.rc" ] || [ $((SECONDS - t0)) -lt $((lim + HOSTPOLL)) ] || {
      if hostssh "$SH_D; $HOSTKILL" 30 < /dev/null > /dev/null 2>&1; then out='was stopped there'; else out='could not be reached over ssh to stop it; it may still run there'; fi
      printf 'conveyor: the suite ran past its time limit, %s s (testTimeout), on %s and %s\n' "$lim" "$SH_NAME" "$out" >> "$1.test"; rm -rf "$1.send" "$1.got"; return 124; }
  done
  rc=$(<"$1.rc"); rm -rf "$1.rc" "$1.send" "$1.got"
  [[ $rc =~ ^[0-9]+$ ]] || rc=1
  return "$rc"
}
# results: the box's run files cleared, and the steps done.
hostfinish() {
  hoststep results
  [ "$SH_KIND" = local ] || hostssh "$SH_D"'; rm -rf "$D/wt.pid" "$D/in"' 30 < /dev/null > /dev/null 2>&1 || :
  hoststep 'done'
}
# `release-run stop`: the run on the box over ssh that the record names, stopped there (HOSTKILL), when the record's
# machine has not reached done.
hoststop() {
  local m
  m=$(jq -ce '.machine | objects | select(.kind == "ssh" and .step != "done")' "$RELRUN" 2>/dev/null) || return 0
  SH_KIND=ssh SH_TARGET=$(jq -r .target <<<"$m") SH_DIR=$(jq -r .dir <<<"$m") && hostd
  hostssh "$SH_D; $HOSTKILL" 30 < /dev/null > /dev/null 2>&1 \
    || echo "conveyor: release-run stop: the suite's run on $(jq -r .name <<<"$m") could not be reached over ssh to stop it; it may still run there" >&2
}
# `conveyor.sh suite-machine check [--json]`: one line a need of the rule's machine, ok or missing: ssh reach (a box
# over ssh), bash 5.1 or later, jq, git and each tool the main checkout's .conveyor/test-machine.sh names on a
# `# tools: <tool>...` line, then its CPU count and test slots (slot_pool's, here or on the box: HOSTFACTS). With
# json: {kind, name, ok, needs: [{need, ok, detail}], cpus, slots}. Exit 0: every need ok; 1: one is missing.
hostcheck() { # [json]
  local tools=() f rc v n=() ok sl=''
  hostrule suite-machine || return 1
  mapfile -t tools < <(sed -n 's/^# tools:[[:space:]]*//p' "$MAIN/.conveyor/test-machine.sh" 2>/dev/null | tr -s ' \t' '\n' | grep -E '^[A-Za-z0-9._+-]+$' | grep -vxE 'jq|git' | sort -u)
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
  f=$(printf '%s\n' "${n[@]}" | jq -cs --arg k "$SH_KIND" --arg nm "$SH_NAME" --arg c "$v" --arg s "$sl" \
    '{kind: $k, name: $nm, ok: all(.[]; .ok), needs: ., cpus: ($c | tonumber? // null), slots: ($s | tonumber? // null)}') || return 1
  if [ "${1:-}" = json ]; then printf '%s\n' "$f"
  else jq -r '"conveyor: suite-machine: the suite runs on \(.name)", (.needs[] | "\(if .ok then "ok" else "missing" end): \(.need): \(.detail)")' <<<"$f"; fi
  jq -e .ok <<<"$f" > /dev/null
}
