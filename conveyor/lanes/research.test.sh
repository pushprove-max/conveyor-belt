#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# The research lane (research.sh): `conveyor.sh lane research create` makes the worktree and its settings, or nothing
# where its sandbox cannot run; in the lane a commit and a push are refused, a Bash command runs in the lane's shell
# (research-bash), where it can change no tracked file whatever it runs, a report write is allowed, and an issue it
# files starts held. Each hook is run as the lane's settings name it, through the shim of the pinned install.
set -uo pipefail
SRC=$(cd "$(dirname "$0")" && pwd -P)
. "$SRC/../tests/wait.sh"
# Each case (t_<case>) runs side by side with the others, on a host and project of its own made by fixture in
# $B/<case> (T); a case after create makes the lane first (lane), and makes what else it goes on from itself.
B=$(mktemp -d); trap 'chmod -R u+w "$B"; rm -rf "$B"' EXIT
fail() { echo "FAIL [$CASE]: $*" >&2; exit 1; }
unset CONVEYOR_FOREMAN CONVEYOR_FOREMAN_DIR CONVEYOR_FOREMAN_ASK CONVEYOR_LANE CONVEYOR_MAIN CLAUDE_CODE_PROMPT_CACHE_TTL
PIN=0123456789abcdef0123456789abcdef01234567
fixture() { # <case>
T=$B/$1
export XDG_CONFIG_HOME=$T/config XDG_DATA_HOME=$T/data HOME=$T/home GIT_CONFIG_GLOBAL=/dev/null
mkdir -p "$XDG_CONFIG_HOME/conveyor" "$HOME"
# The project: a checkout whose pack pins this plugin and names the lane's model and effort.
M=$T/alpha
git init -q -b main "$M" && mkdir -p "$M/.conveyor" \
  && jq --arg p "$PIN" '. + {plugin: {commit: $p}, lanes: {research: {model: "claude-sonnet-5-5", effort: "high"}}}' "$SRC/../lib/test-pack.json" > "$M/.conveyor/project.json" \
  && echo hello > "$M/README.md" && git -C "$M" add -A && git -C "$M" -c user.name=t -c user.email=t@example.com commit -qm init || exit 1
W=$HOME/lanes/alpha-research
jq -n --arg s "$T/state" --arg m "$M" '{stateDir: $s, lanes: {research: {worktree: "~/lanes/alpha-research"}}, records: [{repo: "alpha", main: $m}]}' > "$XDG_CONFIG_HOME/conveyor/host.json"
mkdir -p "$XDG_DATA_HOME/conveyor/versions" && ln -s "$(cd "$SRC/../.." && pwd -P)" "$XDG_DATA_HOME/conveyor/versions/$PIN"
# The temp folder the lane's shell may write is TMPDIR's: one of its own, so the rest of $T is outside it.
mkdir -p "$T/tmp" && export TMPDIR=$T/tmp
}
# lane: the lane made (as the case create makes it), its settings (S), its shell (SH) and the settings' env (LENV).
lane() {
  local out
  out=$(cd "$M" && bash "$SRC/../conveyor.sh" lane research create 2>&1) || fail "create failed: $out"
  S=$W/.claude/settings.local.json; SH=$(jq -r '.env.CLAUDE_CODE_SHELL' "$S")
  # The settings' env, which Claude Code gives its hooks and its Bash calls.
  mapfile -t LENV < <(jq -r '.env | to_entries[] | "\(.key)=\(.value)"' "$S")
}

t_nosandbox() {
CASE=nosandbox
# Where the sandbox cannot run, create says why in one line and makes nothing: no worktree, no settings.
mkdir -p "$T/nosandbox" && printf '#!/bin/sh\necho "no sandbox for this user" >&2; exit 1\n' > "$T/nosandbox/bwrap" \
  && cp "$T/nosandbox/bwrap" "$T/nosandbox/sandbox-exec" && chmod +x "$T/nosandbox/"*
out=$(cd "$M" && PATH=$T/nosandbox:$PATH bash "$SRC/../conveyor.sh" lane research create 2>&1) && fail "create made a lane with no sandbox: $out"
[ "$(wc -l <<<"$out")" = 1 ] && grep -q 'sandbox.*no sandbox for this user' <<<"$out" || fail "create did not say in one line why it made no lane: $out"
[ ! -e "$W" ] && [ "$(git -C "$M" worktree list | wc -l)" = 1 ] || fail "create left a worktree with no sandbox: $(git -C "$M" worktree list)"
}

t_create() {
CASE=create
out=$(cd "$M" && bash "$SRC/../conveyor.sh" lane research create 2>&1) || fail "create failed: $out"
[ "$(git -C "$W" rev-parse --path-format=absolute --git-common-dir)" = "$M/.git" ] || fail "no worktree of the project at the host file's path $W: $out"
# The Board reads each record's lanes from the host file: create writes the lane's folder into this checkout's record.
jq -e --arg w "$W" --arg m "$M" '.records == [{repo: "alpha", main: $m, lanes: {research: {worktree: $w}}}] and .lanes.research.worktree == "~/lanes/alpha-research"' \
  "$XDG_CONFIG_HOME/conveyor/host.json" >/dev/null || fail "create did not write the lane's folder into its record of the host file: $(cat "$XDG_CONFIG_HOME/conveyor/host.json")"
S=$W/.claude/settings.local.json
jq -e '.model == "claude-sonnet-5-5" and .effortLevel == "high" and .env.CLAUDE_CODE_PROMPT_CACHE_TTL == "1h"' "$S" >/dev/null \
  || fail "the lane's settings do not take the pack's model and effort and the 1-hour cache: $(cat "$S")"
SH=$(jq -r '.env.CLAUDE_CODE_SHELL' "$S")
[ "$SH" -ef "$SRC/research-bash" ] && [[ $SH == *bash* ]] || fail "the lane's settings do not run Bash in the lane's shell: $(cat "$S")"
# Bug: the settings name the install by its path, and pruning old installs (prune(), lib/install.sh) removes it under
# the lane: create lists them in the machine's uses file, which prune reads.
grep -qxF "$S" "$XDG_DATA_HOME/conveyor/uses" || fail "create did not list the lane's settings in the uses file: $(cat "$XDG_DATA_HOME/conveyor/uses" 2>&1)"
# Claude Code runs a shell-form hook through CLAUDE_CODE_SHELL_PREFIX and an exec-form one as it is: each is exec form.
jq -e '[.hooks[][].hooks[] | .args | type == "array"] | all' "$S" >/dev/null || fail "a hook of the lane is not in exec form: $(cat "$S")"
# Edit and Write run outside the lane's shell: a tracked file, and the folder holding it, are read-only on disk, so a
# write to it, in place or by a new file moved over it, fails as theirs would.
{ echo changed > "$W/README.md"; } 2>/dev/null && fail "a write in place to a tracked file worked out of the lane's shell"
echo changed > "$T/new" && mv -f "$T/new" "$W/README.md" 2>/dev/null && fail "a file moved over a tracked file worked out of the lane's shell"
[ "$(cat "$W/README.md")" = hello ] || fail "a tracked file changed out of the lane's shell"
cp "$S" "$T/first.json"
out=$(cd "$M" && bash "$SRC/../conveyor.sh" lane research create 2>&1) || fail "a second create failed: $out"
cmp -s "$S" "$T/first.json" || fail "a second create wrote other settings"
[ ! -e "$(dirname "$M")/conveyor-cards" ] || fail "create made a cards folder"
HF=$XDG_CONFIG_HOME/conveyor/host.json; cp "$HF" "$T/host.first"
# Another lane's create holds the host file (its lock) and writes its own lane while this create waits: both lanes
# stay written. Unlocked, this create would put back the file it read first, without the fast lane.
jq 'del(.records[0].lanes)' "$HF" > "$T/h" && mv "$T/h" "$HF"
flock "$HF.lock" sh -c 'touch "$1.held"; until [ -e "$1.go" ]; do sleep 0.1; done' sh "$HF" & lk=$!
until [ -e "$HF.held" ]; do sleep 0.1; done
(cd "$M" && bash "$SRC/../conveyor.sh" lane research create) > "$T/create.out" 2>&1 & cr=$!
# While the lock is held, create waits at it (its flock runs) and has neither ended nor written: a create that took
# no lock would have done both.
wait_until 'under "$cr" flock || ! kill -0 "$cr" 2>/dev/null'; kill -0 "$cr" 2>/dev/null && jq -e '.records[0] | has("lanes") | not' "$HF" >/dev/null \
  || { touch "$HF.go"; fail "create did not wait for the host file's lock: $(cat "$T/create.out"; cat "$HF")"; }
jq '.records[0].lanes.fast.worktree = "~/f"' "$HF" > "$T/h" && mv "$T/h" "$HF"; touch "$HF.go"
wait "$cr" || fail "a create that waited for the host file failed: $(cat "$T/create.out")"
wait "$lk"; rm -f "$HF.held" "$HF.go"
jq -e --arg w "$W" '.records[0].lanes == {fast: {worktree: "~/f"}, research: {worktree: $w}}' "$HF" >/dev/null \
  || fail "a lane written while create waited was lost from the host file: $(cat "$HF")"
# The host file cannot be written (nothing can be made in its folder): create fails and says so, it never reports a
# lane the Board will not show.
jq 'del(.records[0].lanes)' "$HF" > "$T/h" && mv "$T/h" "$HF" && cp "$HF" "$T/host.before" && chmod a-w "$XDG_CONFIG_HOME/conveyor"
out=$(cd "$M" && bash "$SRC/../conveyor.sh" lane research create 2>&1); rc=$?; chmod u+w "$XDG_CONFIG_HOME/conveyor"
[ "$rc" != 0 ] && grep -qF "could not be written into the host file $HF" <<<"$out" && ! grep -q "wrote the research lane's settings" <<<"$out" && cmp -s "$HF" "$T/host.before" \
  || fail "create with a host file that cannot be written (exit $rc): $out; $(cat "$HF")"
# No record whose main is this checkout: nothing is written, and create says what the Board needs. A record named
# for the checkout's folder (alpha) is another project's: a folder's name does not say whose checkout it is. (The
# file's own main stays this checkout, so the state folder, and with it the lane's settings, stay as they were.)
jq --arg m "$M" '.main = $m | .records = [{repo: "alpha", main: "/srv/alpha"}]' "$HF" > "$T/h" && mv "$T/h" "$HF" && cp "$HF" "$T/host.before"
out=$(cd "$M" && bash "$SRC/../conveyor.sh" lane research create 2>&1) && grep -qF "no record of this checkout: the Board shows this lane once a record's lanes.research.worktree names $W" <<<"$out" \
  && cmp -s "$HF" "$T/host.before" || fail "create with no record of the checkout in the host file: $out; $(cat "$HF")"
# A record that spells this checkout another way (a trailing /., a link to it) is still this checkout's: the lane is
# written into it, not passed over as no record, which would leave the Board without the lane. (The file's own main
# stays this checkout, as above.)
ln -s "$M" "$T/alpha-link"
for m in "$M/." "$T/alpha-link"; do
  jq --arg m "$m" --arg own "$M" '.main = $own | .records = [{repo: "other", main: "/srv/other"}, {repo: "alpha", main: $m}]' "$T/host.first" > "$HF"
  out=$(cd "$M" && bash "$SRC/../conveyor.sh" lane research create 2>&1) \
    && jq -e --arg w "$W" --arg m "$m" '.records == [{repo: "other", main: "/srv/other"}, {repo: "alpha", main: $m, lanes: {research: {worktree: $w}}}]' "$HF" >/dev/null \
    || fail "create did not write the lane into a record that names the checkout as $m: $out; $(cat "$HF")"
done
# A record's main is read whole. One with a newline in it that links to this checkout is still this checkout's; one
# that is this checkout's path with a tab or a newline after it names another folder, so the lane is not written
# into it (that would show the lane on the Board under another checkout).
m=$T/alpha$'\n'link; ln -s "$M" "$m"
jq --arg m "$m" --arg own "$M" '.main = $own | .records = [{repo: "alpha", main: $m}]' "$T/host.first" > "$HF"
out=$(cd "$M" && bash "$SRC/../conveyor.sh" lane research create 2>&1) \
  && jq -e --arg w "$W" --arg m "$m" '.records == [{repo: "alpha", main: $m, lanes: {research: {worktree: $w}}}]' "$HF" >/dev/null \
  || fail "create did not write the lane into a record whose main has a newline and links to the checkout: $out; $(cat "$HF")"
for m in "$M"$'\t' "$M"$'\n'; do
  mkdir "$m"
  jq --arg m "$m" --arg own "$M" '.main = $own | .records = [{repo: "other", main: $m}]' "$T/host.first" > "$HF" && cp "$HF" "$T/host.before"
  out=$(cd "$M" && bash "$SRC/../conveyor.sh" lane research create 2>&1) && grep -qF "no record of this checkout" <<<"$out" \
    && cmp -s "$HF" "$T/host.before" || fail "create wrote the lane into a record of another folder ($(printf %q "$m")): $out; $(cat "$HF")"
  rmdir "$m"
done
cp "$T/host.first" "$HF"
# The main checkout is never taken for the lane: its own settings stay as they are.
mkdir -p "$M/.claude" && echo '{}' > "$M/.claude/settings.local.json"
jq --arg m "$M" '.lanes.research.worktree = $m' "$XDG_CONFIG_HOME/conveyor/host.json" > "$T/h" && cp "$XDG_CONFIG_HOME/conveyor/host.json" "$T/h0" && mv "$T/h" "$XDG_CONFIG_HOME/conveyor/host.json"
out=$(cd "$M" && bash "$SRC/../conveyor.sh" lane research create 2>&1) && fail "create took the main checkout for the lane: $out"
[ "$(cat "$M/.claude/settings.local.json")" = '{}' ] || fail "create wrote the main checkout's settings"
mv "$T/h0" "$XDG_CONFIG_HOME/conveyor/host.json"
}

# hook <event> <matcher's tool> <hook input>: every hook the lane's settings run for it, as Claude Code would, in the lane.
hook() {
  local h a
  while IFS= read -r h; do
    mapfile -t a < <(jq -r '.[]' <<<"$h")
    (cd "$W" && CLAUDE_PROJECT_DIR=$W env "${LENV[@]}" "${a[@]}" <<<"$3")
  done < <(jq -c --arg e "$1" --arg t "$2" '.hooks[$e][] | select(.matcher as $m | $m == null or ($t | test("^(" + $m + ")$"))) | .hooks[] | [.command] + .args' "$S")
}
# jailed <command>: the command run as Claude Code runs a Bash call in the lane: by the lane's shell, in the worktree.
jailed() { (cd "$W" && env "${LENV[@]}" "$SH" -c "$1") </dev/null >/dev/null 2>&1; }
bash_in() { jq -cn --arg c "$1" --arg w "$W" '{hook_event_name: "PreToolUse", tool_name: "Bash", cwd: $w, tool_input: {command: $c}}'; }
write_in() { jq -cn --arg t "$1" --arg p "$2" --arg w "$W" '{hook_event_name: "PreToolUse", tool_name: $t, cwd: $w, tool_input: {file_path: $p, content: "x"}}'; }
denied() { jq -se 'any(.[]; .hookSpecificOutput.permissionDecision == "deny")' >/dev/null 2>&1; }

t_start() {
CASE=start
lane
out=$(hook SessionStart '' '{}') && grep -qF 'reports/INDEX.md' <<<"$out" && grep -qF 'starts held' <<<"$out" && grep -qF "$SRC/research-file" <<<"$out" \
  || fail "the session is not told where reports go and that filed work starts held: $out"
}

# The case refused is in four, each on its own lane: git and a program the lane wrote; inline code; rg's options and
# an interpreter's git push; Edit and Write.
t_refused() {
CASE=refused
lane
for c in 'git commit -m x' 'git push origin HEAD' "git -C . 'commit' -am x" 'cd x && git --no-pager push' 'git "$sub" -m x' \
  '/usr/bin/git commit --allow-empty -m x' '/usr/bin/git push origin HEAD' 'git -c alias.ci=commit ci -m x' 'git checkout -- .' \
  'git -ccore.fsmonitor=reports/action.sh status' 'git -C . -ccore.pager=sh log'; do
  hook PreToolUse Bash "$(bash_in "$c")" | denied || fail "a commit, push or git change was not refused: $c"
done
# Claude Code runs plain bash, out of the sandbox, when CLAUDE_CODE_SHELL names no program: every Bash call is refused.
LENV+=("CLAUDE_CODE_SHELL=$T/missing-bash")
hook PreToolUse Bash "$(bash_in 'ls reports')" | denied || fail "a Bash call was not refused when the lane's shell is not there"
unset 'LENV[-1]'
# A program the lane wrote cannot be read, so running it is refused: by its path, or given to a shell or interpreter.
printf 'git commit --allow-empty -m x\n' > "$W/reports/action.sh" && chmod +x "$W/reports/action.sh"
for c in 'bash reports/action.sh' './reports/action.sh' 'reports/action.sh' 'sh < reports/action.sh' 'cat reports/action.sh | sh' \
  'source reports/action.sh' '. ./reports/action.sh' 'f=reports/action.sh; bash "$f"' 'python3 reports/x.py' "\"$W/reports/action.sh\"" \
  '</dev/null ./reports/action.sh' '2> /dev/null reports/action.sh'; do
  [ "$c" != 'python3 reports/x.py' ] || echo 'import os' > "$W/reports/x.py"
  hook PreToolUse Bash "$(bash_in "$c")" | denied || fail "running a program the lane wrote was not refused: $c"
done
}

t_refusedinline() {
CASE=refused
lane
# An interpreter's inline code or input can build a tracked path no word names, so it is refused.
for c in "python3 -c 'open(\"README\"+\".md\",\"w\").write(\"changed\")'" "timeout 60 python3 -Bc 'x'" "echo x | python3" \
  "python3 - <<'EOF'"$'\nx\nEOF' "perl -e 'x'" 'node --eval=x' 'ruby -ne x' 'php -r x' 'deno eval x' "bash -c \"python3 -c 'x'\"" \
  "coproc python3 -c 'open(\"README\"+\".md\",\"w\").write(\"changed\")'; wait" \
  "python3 -m timeit -n 1 -r 1 'open(\"README\"+\".md\",\"w\").write(\"changed\")'" 'python3 -mtimeit x' \
  "</dev/null python3 -c 'open(\"README\"+\".md\",\"w\").write(\"changed\")'" '2> /dev/null perl -e x' \
  "node --title harmless -e'void require(\"fs\").writeFileSync(\"README\"+\".md\",\"changed\")'" \
  "echo x | node --title harmless" "echo 'File.write(\"README\"+\".md\",\"changed\")' | ruby -v" \
  "printf '%s\\n' 'io.open(\"README\"..\".md\",\"w\"):write(\"changed\")' | lua -v" \
  "printf '%s\\n' 'open(\"README\"+\".md\",\"w\").write(\"changed\")' | python3 -X --version" \
  "echo \"\$(python3 -c 'x')\" > reports/x.md" "env bash -c 'cd reports; python3 -c x'"; do
  hook PreToolUse Bash "$(bash_in "$c")" | denied || fail "an interpreter given inline code was not refused: $c"
done
}

t_refusedrg() {
CASE=refused
lane
# rg given an option that runs a command, or one made by an expansion, is no longer read for: the lane's shell keeps
# whatever it runs from changing a tracked file (the sandboxed case), so the guard does not parse rg's options.
for c in "rg --pre 'sed -i s/hello/changed/' hello README.md" 'rg --pre=reports/x.sh hello reports' "rg -n '--pre' cat x" \
  'rg --hostname-bin=reports/x.sh --hyperlink-format=default x reports' \
  'opt=--pre; rg "$opt" '"'sed -i s/hello/changed/' hello README.md" 'rg $(echo --pre) sed hello README.md' \
  'RIPGREP_CONFIG_PATH=reports/rg.conf rg hello README.md' 'rg {--pre,sed} hello README.md' \
  "rg 'a -- b' --pre sed hello README.md" 'rg -e -- --pre sed README.md' "rg '--pre=sed -i s/hello/changed/' hello README.md" \
  'rg -nA 1 --pre sed hello README.md' 'rg -e {x,--pre=sed} hello README.md' "rg \$'\\x2d\\x2dpre' 'sed -i s/hello/changed/' hello README.md" \
  'export RIPGREP_CONFIG_PATH=reports/rg.conf; rg hello README.md' 'x=RIPGREP_CONFIG; export ${x}_PATH=reports/rg.conf; rg hello README.md' \
  'chmod +x reports/push.sh; rg --pre reports/push.sh hello README.md'; do
  out=$(hook PreToolUse Bash "$(bash_in "$c")"); [ -z "$out" ] || fail "the guard still parses rg's options ($c): $out"
done
# An interpreter could run the git push the guard refuses, so its inline code is refused whatever it names.
c="python3 -c 'import subprocess; subprocess.run([\"git\",\"push\",\"origin\",\"HEAD:refs/heads/research-bypass\"])'"
hook PreToolUse Bash "$(bash_in "$c")" | denied || fail "an interpreter running git push was not refused: $c"
}

t_refusedwrite() {
CASE=refused
lane
# A folder the lane may write that holds the worktree, or a file git tracks in reports/, takes no Edit or Write there.
LENV+=("TMPDIR=$HOME")
hook PreToolUse Write "$(write_in Write "$W/README.md")" | denied || fail "a Write to a tracked file in a temp folder holding the worktree was not refused"
unset 'LENV[-1]'
echo x > "$W/reports/kept.md" && git -C "$W" add -f reports/kept.md
hook PreToolUse Write "$(write_in Write "$W/reports/kept.md")" | denied || fail "a Write to a file git tracks in reports/ was not refused"
git -C "$W" rm -q --cached reports/kept.md && rm "$W/reports/kept.md"
for t in Edit Write; do
  hook PreToolUse "$t" "$(write_in "$t" "$W/README.md")" | denied || fail "$t to a tracked file was not refused"
done
hook PreToolUse Edit "$(write_in Edit README.md)" | denied || fail "an edit to a tracked file named relative to the lane was not refused"
hook PreToolUse Write "$(write_in Write "$W/reports/new/../../README.md")" | denied || fail "a Write that climbs out of reports/ was not refused"
# A symbolic link the lane makes to a tracked file is followed: writing it writes the tracked file.
ln -s ../README.md "$W/reports/link.md"
hook PreToolUse Write "$(write_in Write "$W/reports/link.md")" | denied || fail "a Write through a link to a tracked file was not refused"
# A hook written into the git folder would run on a git command the lane may run.
hook PreToolUse Write "$(write_in Write "$M/.git/hooks/reference-transaction")" | denied || fail "a write to a git hook was not refused"
}

# What the four parts of the case sandboxed start from: the lane, with the link to a tracked file the case refused
# leaves in reports/, and with what sandboxed adds before its checks; unchanged says whether a tracked file or the git
# folder changed since.
sandbox_start() {
lane; ln -s ../README.md "$W/reports/link.md"
# The worktree's modes are made writable again, so only the sandbox stands between a command and a tracked file.
chmod -R u+w "$W"
printf '#!/bin/sh\nprintf changed > README.md\n' > "$W/reports/action.sh" && chmod +x "$W/reports/action.sh"
echo 'import os' > "$W/reports/x.py"
mkdir -p "$W/sub" && cp "$W/README.md" "$W/sub/x" && git -C "$W" add sub/x
echo x > "$W/a b.txt" && git -C "$W" add "a b.txt"
find "$M/.git" -type f ! -name index -exec cksum {} + | sort > "$T/gitdir"
git -C "$W" status --porcelain --untracked-files=no > "$T/status"
unchanged() {
  git -C "$W" status --porcelain --untracked-files=no | cmp -s - "$T/status" && [ "$(cat "$W/README.md")" = hello ] \
    && find "$M/.git" -type f ! -name index -exec cksum {} + | sort | cmp -s - "$T/gitdir"
}
}

t_sandboxed() {
CASE=sandboxed
sandbox_start
# Whatever a Bash command runs, in the lane's shell it changes no tracked file and nothing in the git folder. The
# proofs that once passed the guard come first (#136 rg --pre, #137 a git -c running a program the lane wrote, which
# git takes only detached, #147 an ANSI-C quoted option, #148 a brace-expanded one, #135 inline interpreter code), then
# a write through the root of a process outside the sandbox, as /proc shows it.
C=$T/control
git clone -q "$M" "$C" && mkdir -p "$C/reports" && cp "$W/reports/action.sh" "$C/reports/" || fail "could not make the control clone"
# A proof whose program is missing changes nothing in the lane either, and shows nothing: rg is required.
command -v rg >/dev/null || fail "rg is not installed, so the rg proofs run nothing"
proofs=('rg --pre reports/action.sh hello README.md' 'git -c core.fsmonitor=reports/action.sh status'
  "rg \$'\\x2d\\x2dpre' reports/action.sh hello README.md" 'rg {--pre,reports/action.sh} hello README.md'
  "python3 -c 'open(\"README\"+\".md\",\"w\").write(\"changed\")'"
  'for p in /proc/[0-9]*/root; do printf changed > "$p$PWD/README.md"; done')
for c in "${proofs[@]}"; do
  # Out of the sandbox, in the clone, each proof but the /proc one (which would write through other processes' roots)
  # changes a tracked file, so its staying unchanged in the lane is the sandbox's doing.
  if [[ $c != *'/proc/'* ]]; then
    (cd "$C" && bash -c "$c") </dev/null >/dev/null 2>&1
    [ "$(cat "$C/README.md")" != hello ] || fail "the proof changes no tracked file even out of the sandbox, so it shows nothing: $c"
    git -C "$C" reset -q --hard origin/main
  fi
  jailed "$c"; unchanged || fail "a proof command changed a tracked file in the lane's shell: $c: $(git -C "$W" status --porcelain)"
done
}

t_sandboxedhost() {
CASE=sandboxed
sandbox_start
# Its /proc shows no process outside it (this test's shell), whose root it could write through where the kernel allows.
jailed "[ ! -e /proc/$$ ]" || fail "the lane's shell sees a process outside it in /proc"
# Nor does it write the host's /dev/shm, outside the folders the lane may write. This name and the abstract socket's
# below are this run's own (B's, not the case's T), so two runs side by side do not take each other's.
shm=/dev/shm/${B##*/}-research
if [ -d /dev/shm ]; then
  jailed "printf changed > $shm"; [ ! -e "$shm" ] || { rm -f "$shm"; fail "the lane's shell wrote the host's /dev/shm"; }
fi
# Nor does it reach a host server's Unix socket (a tmux one, say), which would run its command outside: one in the temp
# folder it may write, or (Linux) an abstract one. The server runs each command it is sent; out of the sandbox it runs.
for a in "$TMPDIR/cmd.sock" $([ "$(uname -s)" = Darwin ] || echo "@${B##*/}-cmd"); do
  python3 -c 'import socket, subprocess, sys
a = sys.argv[1].replace("@", "\0", 1); s = socket.socket(socket.AF_UNIX); s.settimeout(60); s.bind(a); s.listen(); print(flush=True)
while True: c = s.accept()[0]; subprocess.run(c.makefile().read(), shell=True); c.close()' "$a" > "$T/srv" &
  srv=$!; wait_until '[ -s "$T/srv" ] || ! kill -0 "$srv" 2>/dev/null'; [ -s "$T/srv" ] || fail "the command server did not start on $a"
  send="python3 -c 'import socket, sys; s = socket.socket(socket.AF_UNIX); s.connect(sys.argv[1].replace(\"@\", \"\\0\", 1)); s.sendall(sys.argv[2].encode())' '$a'"
  bash -c "$send 'touch $T/served'"; wait_until '[ -e "$T/served" ] || ! kill -0 "$srv" 2>/dev/null'; [ -e "$T/served" ] || fail "the command server on $a ran nothing"
  rm "$T/served"; jailed "$send \"chmod u+w '$W/README.md'; printf changed > '$W/README.md'\""; jailed "$send 'touch $T/served-jailed'"
  bash -c "$send 'touch $T/served'"; wait_until '[ -e "$T/served" ] || ! kill -0 "$srv" 2>/dev/null'; [ -e "$T/served" ] || fail "the command server on $a ran nothing"
  kill "$srv"; wait "$srv" 2>/dev/null; rm -f "$T/srv" "$T/served" "$TMPDIR/cmd.sock"
  [ ! -e "$T/served-jailed" ] && unchanged || fail "the lane's shell ran a command outside through a host server's socket ($a): $(git -C "$W" status --porcelain)"
done
}

t_sandboxedarch() {
CASE=sandboxed
sandbox_start
# A Linux host of another architecture still gets a lane, its filter checking that architecture's own calls: the
# architecture, socketcall (where there is one), socket and socketpair (a stand-in bwrap shows the filter it is given).
if [ "$(uname -s)" = Linux ]; then
  mkdir -p "$T/arch" && printf '#!/bin/sh\n[ "$1" = -m ] && { echo "$ARCH"; exit; }\nexec %s "$@"\n' "$(command -v uname)" > "$T/arch/uname" \
    && printf '#!/usr/bin/env bash\nwhile [ "$1" != --seccomp ]; do shift; done; od -An -tx1 -v <&"$2" | tr -d " \\n" > "$T/arch/filter"\n' > "$T/arch/bwrap" \
    && chmod +x "$T/arch/"* || fail "could not make the stand-in uname and bwrap"
  # k <value>: the value as the filter holds it, little-endian.
  k() { printf '%02x' $(($1 & 255)) $(($1 >> 8 & 255)) $(($1 >> 16 & 255)) $(($1 >> 24 & 255)); }
  for x in 'armv7l 0x40000028 102 281 288' 'armv6l 0x40000028 102 281 288' 'riscv64 0xc00000f3 425 198 199' \
    'loongarch64 0xc0000102 425 198 199' 'ppc64le 0xc0000015 102 326 333'; do
    read -r m arch call sock pair <<<"$x"; rm -f "$T/arch/filter"
    (cd "$W" && ARCH=$m T=$T PATH=$T/arch:$PATH env "${LENV[@]}" "$SH" -c true) </dev/null >/dev/null 2>&1 \
      || fail "the lane's shell runs nothing on a $m host"
    f=$(cat "$T/arch/filter" 2>/dev/null)
    [ "${f:16:16}" = "1500000c$(k "$arch")" ] && [ "${f:80:16}" = "15000800$(k "$call")" ] \
      && [ "${f:96:16}" = "15000002$(k "$sock")" ] && [ "${f:144:16}" = "15000003$(k "$pair")" ] \
      || fail "the filter of a $m host does not check its own calls: $f"
  done
fi
}

t_sandboxedwrites() {
CASE=sandboxed
sandbox_start
# Every Bash write the guard once read for (a redirection, a command naming the file, a link, a quoted name, a program
# the lane wrote, an interpreter, a reader running a command) fails in the lane's shell, and so does a commit.
for c in "printf 'changed\n' > README.md" 'echo x >> ./README.md' "echo x > $W/README.md" 'cp /dev/null README.md' 'sed -i s/a/b/ README.md' \
  'cat README.md | tee README.md' 'rm -rf sub' 'cd sub && echo x > x' 'f=README.md; echo x > $f' 'mv README.md reports/' \
  "sed -i s/a/b/ \$'\\x52EADME.md'" 'echo changed > reports/link.md' 'cp /dev/null reports/link.md' \
  'echo changed > "a b.txt"' "echo changed > 'a b.txt'" 'echo changed > a\ b.txt' 'cp /dev/null "a b.txt"' \
  'bash reports/action.sh' './reports/action.sh' 'sh < reports/action.sh' 'cat reports/action.sh | sh' '. ./reports/action.sh' \
  'python3 reports/x.py' "\"$W/reports/action.sh\"" "timeout 60 python3 -Bc 'x'" "echo 'open(\"README\"+\".md\",\"w\")' | python3" \
  "perl -e 'open(F, \">README.md\")'" "node -e 'require(\"fs\").writeFileSync(\"README\"+\".md\",\"changed\")'" \
  "coproc python3 -c 'open(\"README\"+\".md\",\"w\").write(\"changed\")'; wait" 'rg --pre=reports/action.sh hello README.md' \
  'opt=--pre; rg "$opt" '"'sed -i s/hello/changed/' hello README.md" 'rg $(echo --pre) sed hello README.md' \
  "rg '--pre=sed -i s/hello/changed/' hello README.md" 'rg -e {x,--pre=sed} hello README.md' \
  'git commit --allow-empty -m x' 'git -c alias.ci=commit ci --allow-empty -m x' 'git checkout -- .' 'git rm -q README.md' \
  "echo x > $M/.git/hooks/reference-transaction"; do
  jailed "$c"; unchanged || fail "a Bash command changed a tracked file or the git folder in the lane's shell: $c: $(git -C "$W" status --porcelain)"
done
# A folder the lane may write that holds the worktree, or a file git tracks in reports/, would let a write through:
# the lane's shell runs nothing then.
LENV+=("TMPDIR=$HOME")
jailed 'echo changed > README.md' && fail "the lane's shell ran with a temp folder holding the worktree"
unset 'LENV[-1]'
echo x > "$W/reports/kept.md" && git -C "$W" add -f reports/kept.md && git -C "$W" status --porcelain --untracked-files=no > "$T/status"
jailed 'echo changed > reports/kept.md' && fail "the lane's shell ran with a file git tracks in reports/"
[ "$(cat "$W/reports/kept.md")" = x ] || fail "the lane's shell changed a file git tracks in reports/"
git -C "$W" rm -q --cached reports/kept.md && rm "$W/reports/kept.md"
git -C "$W" rm -q --cached sub/x "a b.txt" && rm -rf "$W/sub" "$W/a b.txt" "$W/reports/action.sh" "$W/reports/x.py" "$W/reports/link.md" "$W/reports/README.md"
# The folders the lane may write take a write in the lane's shell: a report, the lane's folder, the temp folder.
jailed 'mkdir -p reports/2026-11-13 && echo found > reports/2026-11-13/finding.md && echo x > "$CONVEYOR_RESEARCH_DIR/x" && echo x > "$TMPDIR/x"' \
  && [ "$(cat "$W/reports/2026-11-13/finding.md")" = found ] && [ -f "$T/state/lanes/research/x" ] && [ -f "$T/tmp/x" ] \
  || fail "the lane's shell could not write a report, the lane's folder or the temp folder"
rm -rf "$W/reports/2026-11-13" "$T/state/lanes/research/x" "$T/tmp/x"
}

t_allowed() {
CASE=allowed
lane
# The four rg '$HOME' cases guard the literal-dollar false refusal: a quoted or escaped $ is a search pattern, not an expansion.
for c in 'git status' 'git log --oneline' 'ls reports' 'cat README.md' 'git diff -- README.md' 'grep -n hello README.md 2>&1' \
  'rg -n --pre-glob x hello README.md' "rg -- '--pre' README.md" "rg -n 'hello$' README.md" 'rg -n -- --pre README.md' \
  'rg RIPGREP_CONFIG_PATH README.md' 'rg -n "python3 -c" README.md' 'rg -ne --pre README.md' 'rg --glob=*.md -A 1 hello reports' \
  "rg '\\\$HOME' README.md" "rg '\$HOME' README.md" 'rg \$HOME README.md' "rg \"\\\$HOME\" README.md" \
  'mkdir -p reports/2026-11-12 && echo found > reports/2026-11-12/finding.md' 'echo x >> reports/INDEX.md' \
  'python3 --version' 'node -v' 'perl -v' 'ruby --version' "printf '%s\\n' '(python3 -c \"print(1)\")' > reports/example.md"; do
  out=$(hook PreToolUse Bash "$(bash_in "$c")"); [ -z "$out" ] || fail "a read-only command was refused ($c): $out"
done
out=$(hook PreToolUse Write "$(write_in Write "$W/reports/2026-11-12/finding.md")"); [ -z "$out" ] || fail "a report write was refused: $out"
mkdir -p "$W/reports/2026-11-12" && echo found > "$W/reports/2026-11-12/finding.md" && echo '2026-11-12 x' > "$W/reports/INDEX.md"
[ -z "$(git -C "$W" status --porcelain -- reports)" ] || fail "reports are not untracked and out of sight: $(git -C "$W" status --porcelain)"
}

t_held() {
CASE=held
lane
# An issue the lane files starts held: every record starts new issues held before the command runs, and the issue
# linked after it is held in its record. CONVEYOR_FOREMAN_ASK is foreman/lib.sh's seam for a Conveyor command.
: > "$T/calls"
export CONVEYOR_FOREMAN_ASK="echo \"\$CONVEYOR_REPO \$CONVEYOR_CMD\" >> $T/calls; [ \"\$CONVEYOR_CMD\" != control ] || echo '{\"start\":\"queue\"}'"
cmd='gh issue create --title example --body example'
out=$(hook PreToolUse Bash "$(bash_in "$cmd")"); [ -z "$out" ] || fail "filing an issue was refused: $out"
grep -qx 'alpha control start held' "$T/calls" || fail "new issues do not start held before the filing command runs: $(cat "$T/calls")"
out=$(hook PostToolUse Bash "$(jq -cn --arg c "$cmd" '{hook_event_name: "PostToolUse", tool_name: "Bash", tool_input: {command: $c},
  tool_response: {stdout: "https://github.com/example/alpha/issues/41\n", stderr: ""}}')")
grep -qx 'alpha control adopt 41' "$T/calls" || fail "the issue the lane filed is not held: $(cat "$T/calls")"
[ "$(sed -n '$p' "$T/calls")" = 'alpha control start queue' ] || fail "new issues are not set back to the queue once the filed one is held: $(cat "$T/calls")"
[ -d "$T/state/lanes/research" ] || fail "the lane's folder is not in the state folder"
# Filing through GitHub's API starts held just the same.
: > "$T/calls"
out=$(hook PreToolUse Bash "$(bash_in 'gh api repos/example/alpha/issues -f title=example -f body=example')"); [ -z "$out" ] || fail "filing by the API was refused: $out"
grep -qx 'alpha control start held' "$T/calls" || fail "new issues do not start held before an API filing runs: $(cat "$T/calls")"
# A title or body that names a tracked file is no write to it.
for c in 'gh issue create --title README.md --body example' 'gh -R example/alpha issue create --title "fix README.md" --body-file reports/x.md' \
  'gh api repos/example/alpha/issues -f title=README.md -f body=example'; do
  out=$(hook PreToolUse Bash "$(bash_in "$c")"); [ -z "$out" ] || fail "filing an issue that names a tracked file was refused ($c): $out"
done
# A GraphQL request read from a file cannot be read: it starts held too (the shared filing folder, its list of records
# set held and its marks of filings in flight, is emptied: the cases above ran no filed hook).
: > "$T/calls"; rm -rf "$T/config/conveyor/filing"
out=$(hook PreToolUse Bash "$(bash_in 'gh api graphql -F query=@reports/create.graphql')"); [ -z "$out" ] || fail "filing by a GraphQL file was refused: $out"
grep -qx 'alpha control start held' "$T/calls" || fail "new issues do not start held before a GraphQL request from a file runs: $(cat "$T/calls")"
rm -rf "$T/config/conveyor/filing"
}

t_network() {
CASE=network
lane
# The lane's shell reaches GitHub only by the lane's filing command: the proofs of #138, #157, #158 and #159 (curl
# --netrc and gh api on the issues endpoint, with URL globbing, path normalization and quoted semicolons) each connect
# to GitHub's API out of the shell and connect nowhere in it. A proxy every client here goes through (HTTPS_PROXY)
# stands in for the network: a connection it logs is one that would reach GitHub, and it answers each with a refusal.
python3 -c 'import socket, sys
s = socket.socket(); s.bind(("127.0.0.1", 0)); s.listen(); print(s.getsockname()[1], flush=True)
while True:
    c = s.accept()[0]; c.settimeout(5)
    try: l = c.makefile("rb").readline().decode(errors="replace").strip()
    except OSError: l = "?"
    with open(sys.argv[1], "a") as f: f.write(l + "\n")
    try: c.sendall(b"HTTP/1.1 403 Forbidden\r\nContent-Length: 0\r\nConnection: close\r\n\r\n")
    except OSError: pass
    c.close()' "$T/proxy.log" > "$T/proxy.port" &
proxy=$!; wait_until '[ -s "$T/proxy.port" ] || ! kill -0 "$proxy" 2>/dev/null'; [ -s "$T/proxy.port" ] || fail "the proxy did not start"
export HTTPS_PROXY=http://127.0.0.1:$(cat "$T/proxy.port") GH_TOKEN=example GH_CONFIG_DIR=$T/gh; export https_proxy=$HTTPS_PROXY
unset NO_PROXY no_proxy
printf 'machine api.github.com login example password example\n' > "$HOME/.netrc"
command -v curl >/dev/null && command -v gh >/dev/null || fail "curl or gh is not installed, so the proofs run nothing"
proofs=("curl --netrc -sS -d '{\"title\":\"example\"}' https://api.github.com/repos/example/alpha/issues"
  "curl --netrc -sS -d '{\"title\":\"example\"}' 'https://api.github.com/repos/example/alpha/issue[r-t]'"
  "curl --netrc -sS -d '{\"title\":\"example\"}' https://api.github.com/repos/example/alpha/{x,issues}"
  "curl --netrc -sS -d '{\"title\":\"example\"}' https://api.github.com/repos/example/alpha/x/../issues"
  "curl --netrc -sS -d '{\"title\":\"a;b\"}' -H 'Accept: application/json; q=1' 'https://api.github.com/repos/example/alpha/issues'"
  'gh api repos/example/alpha/issues -f title=example' 'gh api repos/example/alpha/./x/../issues -f title=example'
  "gh api 'repos/example/alpha/issues' -f 'title=a; b' -f 'body=c;d'" 'gh issue create -R example/alpha --title example --body example')
for c in "${proofs[@]}"; do
  : > "$T/proxy.log"; (cd "$W" && timeout 60 bash -c "$c") </dev/null >/dev/null 2>&1
  grep -q 'api\.github\.com' "$T/proxy.log" || fail "the proof reaches no GitHub API even out of the lane's shell, so it shows nothing: $c: $(cat "$T/proxy.log")"
  : > "$T/proxy.log"; (cd "$W" && timeout 60 env "${LENV[@]}" "$SH" -c "$c") </dev/null >/dev/null 2>&1
  [ ! -s "$T/proxy.log" ] || fail "a proof connected out of the lane's shell: $c: $(cat "$T/proxy.log")"
done
kill "$proxy"; wait "$proxy" 2>/dev/null
unset HTTPS_PROXY https_proxy GH_TOKEN GH_CONFIG_DIR; rm -f "$HOME/.netrc"
# The lane's filing command, run in the lane's shell, files one issue, outside it (the stand-in gh writes a folder the
# shell cannot), and that issue is held: new issues start held before it is filed, it is held, then they start in the
# queue again. What the shell writes in the lane's folder (a record named as already set held by filing) changes none
# of that, and `serve` is a title like any other.
printf 'alpha\n' > "$T/state/lanes/research/filing-held"
: > "$T/calls" && mkdir -p "$T/ghbin" \
  && printf '#!/bin/sh\n[ "$1 $2" = "issue create" ] || exit 1\n{ printf "%%s\\n" "$*"; cat; } >> %s\necho https://github.com/example/alpha/issues/42\n' "$T/issues" > "$T/ghbin/gh" \
  && chmod +x "$T/ghbin/gh" || fail "could not make the stand-in gh"
export CONVEYOR_FOREMAN_ASK="echo \"\$CONVEYOR_REPO \$CONVEYOR_CMD\" >> $T/calls; [ \"\$CONVEYOR_CMD\" != control ] || echo '{\"start\":\"queue\"}'"
for title in 'example title' serve; do
  : > "$T/calls"; : > "$T/issues"
  out=$(cd "$W" && PATH=$T/ghbin:$PATH env "${LENV[@]}" "$SH" -c "printf 'found\n' | $SRC/research-file '$title'" 2>&1) \
    || fail "the filing command failed in the lane's shell: $title: $out"
  [ "$out" = https://github.com/example/alpha/issues/42 ] || fail "the filing command did not print the issue's link: $title: $out"
  [ "$(grep -c '^issue create' "$T/issues")" = 1 ] && grep -qx -- "issue create --title $title --body-file -" "$T/issues" && grep -qx found "$T/issues" \
    || fail "the filing command did not file one issue with its title and body: $(cat "$T/issues")"
  [ "$(cat "$T/calls")" = $'alpha control\nalpha control start held\nalpha control adopt 42\nalpha control start queue' ] \
    || fail "the issue filed was not held, its record starting new issues held first and in the queue again after: $title: $(cat "$T/calls")"
done
# The filer keeps what it relies on where the shell cannot write it.
jailed "printf 'alpha\n' > '$T/state/lanes/research-filer/filing-held'; touch '$T/state/lanes/research-filer/x'; printf 'x\n' >> '$T/config/conveyor/filing/in'; printf 'alpha\n' >> '$T/config/conveyor/filing/held'"
[ ! -s "$T/state/lanes/research-filer/filing-held" ] && [ ! -e "$T/state/lanes/research-filer/x" ] || fail "the lane's shell wrote the filer's folder"
[ ! -s "$T/config/conveyor/filing/in" ] && [ ! -s "$T/config/conveyor/filing/held" ] || fail "the lane's shell wrote the shared filing folder"
# Nor through a link: a config folder named by a link into the temp folder the shell may write runs nothing.
mkdir -p "$TMPDIR/config" && ln -s "$TMPDIR/config" "$HOME/config-link"
LENV+=("XDG_CONFIG_HOME=$HOME/config-link")
jailed "touch '$TMPDIR/config/conveyor/filing/in'" && fail "the lane's shell ran with the shared filing folder, named by a link, in its temp folder"
unset 'LENV[-1]'; rm -rf "$HOME/config-link" "$TMPDIR/config"
# One filer files at a time: while another holds the turn (its record set to start new issues held, its issue not yet
# held), a second files nothing and so never starts new issues in the queue again under it; it files once the turn is free.
: > "$T/calls"; : > "$T/issues"; mkfifo "$T/turn"
flock "$T/state/lanes/research-filer/filing.lock" sh -c "read x < '$T/turn'" & turn=$!
until flock -n "$T/state/lanes/research-filer/filing.lock" true; [ $? = 1 ]; do sleep 0.1; done
(cd "$W" && PATH=$T/ghbin:$PATH env "${LENV[@]}" "$SH" -c "printf 'found\n' | $SRC/research-file second" > "$T/second" 2>&1) & second=$!
wait_until 'under "$second" flock || ! kill -0 "$second" 2>/dev/null' # it waits at the turn's lock, or has ended
[ ! -s "$T/calls" ] && [ ! -s "$T/issues" ] || fail "a filer filed while another held the turn: $(cat "$T/calls" "$T/issues")"
echo go > "$T/turn"; wait "$turn"; wait "$second" || fail "the waiting filer failed once the turn was free: $(cat "$T/second")"
[ "$(cat "$T/calls")" = $'alpha control\nalpha control start held\nalpha control adopt 42\nalpha control start queue' ] && grep -qx 'issue create --title second --body-file -' "$T/issues" \
  || fail "the waiting filer did not file its issue held once the turn was free: $(cat "$T/calls" "$T/issues")"
# Nor do the lane's own hooks start new issues in the queue again while the filer holds the turn: a Bash call's filing
# hook set them held (so the filer, seeing them held, sets nothing), and its filed hook waits for the turn to be free.
: > "$T/calls"; printf 'alpha\n' > "$T/config/conveyor/filing/held"
flock "$T/state/lanes/research-filer/filing.lock" sh -c "read x < '$T/turn'" & turn=$!
until flock -n "$T/state/lanes/research-filer/filing.lock" true; [ $? = 1 ]; do sleep 0.1; done
cmd='gh issue create --title example --body example'
hook PostToolUse Bash "$(jq -cn --arg c "$cmd" '{hook_event_name: "PostToolUse", tool_name: "Bash", tool_input: {command: $c}, tool_response: {stdout: "", stderr: ""}}')" > "$T/filed" 2>&1 & filed=$!
wait_until 'under "$filed" flock || ! kill -0 "$filed" 2>/dev/null' # it waits at the turn's lock, or has ended
! grep -q 'start queue' "$T/calls" || { echo go > "$T/turn"; fail "the lane's filed hook started new issues in the queue again while the filer held the turn: $(cat "$T/calls")"; }
echo go > "$T/turn"; wait "$turn"; wait "$filed"
[ "$(cat "$T/calls")" = 'alpha control start queue' ] && [ ! -s "$T/config/conveyor/filing/held" ] \
  || fail "the lane's filed hook did not start new issues in the queue again once the turn was free: $(cat "$T/calls" "$T/filed")"
}

# Every case at once, each in a subshell on its own fixture; each one's output is shown once all have ended, and the
# test passes only when each case ran to its end.
cases=(nosandbox create start refused refusedinline refusedrg refusedwrite sandboxed sandboxedhost sandboxedarch sandboxedwrites allowed held network)
# The cases CONVEYOR_SHELL_TEST_CASE names (comma-separated), as the runner selects them; all of them with none set.
SEL=${CONVEYOR_SHELL_TEST_CASE:-${cases[*]}}; SEL=${SEL//,/ }
for one_case in $SEL; do case " ${cases[*]} " in *" $one_case "*) ;; *) echo "unknown case $one_case" >&2; exit 2 ;; esac; done
read -ra cases <<<"$SEL"
# (A case's own variables, as its loops' c, are its own: the case's name is in one none of them uses.)
for one_case in "${cases[@]}"; do
  (CASE=$one_case; fixture "$one_case"; "t_$one_case"; : > "$B/$one_case.passed") > "$B/$one_case.out" 2>&1 &
done
wait
bad=0
for one_case in "${cases[@]}"; do
  cat "$B/$one_case.out" >&2
  [ -e "$B/$one_case.passed" ] || { bad=1; [ -s "$B/$one_case.out" ] || echo "FAIL [$one_case]: ended with no word" >&2; }
done
[ "$bad" = 0 ] || exit 1
echo "research lane: all cases passed"
