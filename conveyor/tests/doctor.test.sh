#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: doctor, and setup's and doctor's lines for the project's CLAUDE.md and AGENTS.md. The sample is
# setup.test.sh's; the helpers here (doctordone, without, uninstalled, boardup) are other case files' too.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# Bug (#91): setup and doctor said nothing of the project's CLAUDE.md and AGENTS.md, so a project without them gave
# every card's sessions no project context and no one was told. The case runs setup, then doctor, which must print
# the same line for each file; setup must write and change neither file.
agentlines() { grep -E '^(ok|missing): (CLAUDE|AGENTS)\.md' <<<"$1"; }
agentsetup() { # <case's word>: $X, $out (setup's output) and $doc (doctor's, which exits 0)
  X=$D/conveyor/conveyor.sh
  out=$(cd "$S" && bash "$X" setup --fast-lane no --research-lane no --owner Dana --product src/ --test t --survey no --pin 2>&1) || fail "setup exited non-zero ($1): $out"
  # A service whose conveyor.sh is there is no missing piece (as in t_doctor).
  mkdir -p "$XDG_CONFIG_HOME/systemd/user" && printf '[Service]\nExecStart="/bin/bash" "%s" machine\n' "$V/$B/conveyor/conveyor.sh" > "$XDG_CONFIG_HOME/systemd/user/conveyor-machine.service"
  doc=$(cd "$S" && bash "$X" doctor 2>&1) || fail "doctor failed ($1), when only the instruction files may be missing, and they are not a fault: $doc"
  [ "$(agentlines "$out")" = "$(agentlines "$doc")" ] || fail "doctor did not print setup's lines for CLAUDE.md and AGENTS.md ($1): setup: $out; doctor: $doc"
}
t_agentfilesmissing() {
  local X out doc; sample; git -C "$S" rm -q CLAUDE.md AGENTS.md || fail "the sample's files were not removed"
  agentsetup missing
  grep -q "^missing: CLAUDE.md at the root of $S, .*; fix: run /conveyor-belt:setup" <<<"$out" && grep -q "^missing: AGENTS.md at the root of $S, .*; fix: " <<<"$out" \
    && [ "$(agentlines "$out" | wc -l)" = 2 ] || fail "setup did not print one missing: line for each of CLAUDE.md and AGENTS.md: $out"
  # The only missing lines doctor prints are those two: the rest of the sample is in place.
  [ "$(grep -c '^missing:' <<<"$doc")" = 2 ] || fail "doctor printed other missing lines: $doc"
  [ ! -e "$S/CLAUDE.md" ] && [ ! -e "$S/AGENTS.md" ] || fail "setup wrote an instruction file"
}
# Both files there: t_doctor, whose setup and doctor runs are this case's.

# Bug (R143): setup's step 4 wrote a missing CLAUDE.md at the root of the checkout it ran in, but doctor checks the
# main checkout, so from a linked worktree (the fast lane) doctor still said it was missing. Step 4 writes it in the
# folder doctor's missing: line names: there, doctor run in the worktree says ok.
t_agentfileslane() {
  local X out f w=$T/$CASE/lane; sample; X=$D/conveyor/conveyor.sh
  git -C "$S" rm -q CLAUDE.md && git -C "$S" commit -qm 'no CLAUDE.md' && git -C "$S" worktree add -q --detach "$w" || fail "the linked worktree with no CLAUDE.md"
  # Step 4 is done by the setup session from this text, which no case can run: the text is checked.
  tr -s ' \n' '  ' < "$SRC/../commands/setup.md" | grep -qF 'write that file in the folder the `missing:` line names after "at the root of"' \
    || fail "commands/setup.md step 4 does not write the file in the folder doctor's missing: line names"
  out=$(cd "$w" && bash "$X" doctor 2>&1); f=$(sed -n 's/^missing: CLAUDE\.md at the root of \(.*\), the project.s instructions .*/\1/p' <<<"$out")
  [ "$f" = "$S" ] || fail "doctor run in the linked worktree $w did not name the main checkout $S as the root CLAUDE.md is missing from: $out"
  echo '# Sample' > "$f/CLAUDE.md"
  out=$(cd "$w" && bash "$X" doctor 2>&1); grep -q '^ok: CLAUDE\.md, ' <<<"$out" || fail "doctor run in $w, with CLAUDE.md written in $f, did not say ok: $out"
  # Bug: step 4's commit command, run from the worktree, committed the whole index of the main checkout, so a file
  # staged there for other work went in with CLAUDE.md. The command step 4 gives, run as given, commits CLAUDE.md alone.
  local cmd; cmd=$(tr -s ' \n' '  ' < "$SRC/../commands/setup.md" | sed -n 's/.*in that folder: `\([^`]*\)`.*/\1/p')
  cmd=${cmd//<that folder>/$(printf %q "$f")}; cmd=${cmd// AGENTS.md/}
  echo other > "$f/other.txt" && git -C "$f" add other.txt && (cd "$w" && eval "$cmd" >/dev/null) || fail "step 4's commit command failed: $cmd"
  [ "$(git -C "$f" show --name-only --format= HEAD)" = CLAUDE.md ] && [ "$(git -C "$f" diff --cached --name-only)" = other.txt ] \
    || fail "step 4's command '$cmd', with other.txt staged in $f, committed $(git -C "$f" show --name-only --format= HEAD | paste -sd' ')"
}

# A PATH holding every program this one does but <name>...: a folder of links, so the machine's own copy is gone too.
# The first of a name on PATH is the one linked; all are made by one ln, not one ln a program (thousands of them).
without() { local p=$T/$CASE/without-${*// /-} d f n fs=(); local -A seen; mkdir -p "$p"
  for d in ${PATH//:/ }; do for f in "$d"/*; do n=${f##*/}
    case " $* " in *" $n "*) ;; *) [ -x "$f" ] && [ -z "${seen["$n"]:-}" ] && seen["$n"]=1 && fs+=("$f") ;; esac
  done; done; [ ${#fs[@]} = 0 ] || ln -s "${fs[@]}" "$p/"; echo "$p"; }
# Each doctor case below is the sample, set up with its pin (doctordone), and the doctor runs it is about: one after
# another, about 3 s a run, they made one case of 10 s.
doctordone() { sample; X=$D/conveyor/conveyor.sh; (cd "$S" && bash "$X" setup --fast-lane no --research-lane no --owner Dana --product src/ --test t --survey no --pin >/dev/null) || fail "setup exited non-zero"; }
# The Board running (#108), for a doctor run with $T/$CASE/board first on PATH and CONVEYOR_DASHBOARD_PORT=8791: curl
# gets its login page, under its own certificate (there, beside the case's login store, sample), on the port the Board
# is set to.
boardup() {
  local tls; tls=$(dirname "${CONVEYOR_DASHBOARD_AUTH:?sample sets it}")/dashboard-tls
  mkdir -p "$T/$CASE/board" "$tls" && : > "$tls/cert.pem" && printf '#!/bin/sh\ncase "$*" in "-q -s --cacert "*/dashboard-tls/cert.pem" --max-time 2 https://127.0.0.1:8791/login") echo "<title>Conveyor Board</title>";; *) exit 7;; esac\n' > "$T/$CASE/board/curl" \
    && chmod +x "$T/$CASE/board/curl" || fail "the curl stub was not made"
}
# The pinned commit's install removed, as the fix of a damaged one leaves it.
uninstalled() { chmod -R u+w "$V/$B" && rm -rf "${V:?}/$B"; }

# Bugs: doctor passes with a piece missing, or names one without its fix; a missing jq or git stops it before it
# names the rest.
t_doctor() {
  local X out said; sample; X=$D/conveyor/conveyor.sh
  # doctordone's setup, its output kept for its CLAUDE.md and AGENTS.md lines (#91, at the end).
  said=$(cd "$S" && bash "$X" setup --fast-lane no --research-lane no --owner Dana --product src/ --test t --survey no --pin 2>&1) || fail "setup exited non-zero: $said"
  # The last card test run recorded test times (times), the one before it none: no word of missing times.
  doctortests '{}' '{times: {"a.test": 1}}'
  # A service whose conveyor.sh is there (the machine's, on the pinned install) is no missing piece.
  mkdir -p "$XDG_CONFIG_HOME/systemd/user" && printf '[Service]\nExecStart="/bin/bash" "%s" machine\n' "$V/$B/conveyor/conveyor.sh" > "$XDG_CONFIG_HOME/systemd/user/conveyor-machine.service"
  # The Board's stand-in leaves a good certificate in the home's rulings folder as it is. Bug caught (#200): it emptied
  # ~/.claude/rulings/dashboard-tls/cert.pem, the real Board's, which then failed on every start.
  local h=$T/$CASE/home sum; mkdir -p "$h/.claude/rulings/dashboard-tls" \
    && openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -days 1 -subj /CN=localhost \
      -keyout "$h/.claude/rulings/dashboard-tls/key.pem" -out "$h/.claude/rulings/dashboard-tls/cert.pem" 2>/dev/null \
    && sum=$(cksum < "$h/.claude/rulings/dashboard-tls/cert.pem") || fail "the good certificate was not made"
  HOME=$h boardup
  [ "$(cksum < "$h/.claude/rulings/dashboard-tls/cert.pem")" = "$sum" ] || fail "fixture_keeps_the_home_certificate: boardup changed the certificate in HOME's rulings folder"
  out=$(cd "$S" && PATH=$T/$CASE/board:$PATH CONVEYOR_DASHBOARD_PORT=8791 bash "$X" doctor 2>&1) || fail "doctor failed with everything in place: $out"
  grep -qx 'ok: the Board, running at https://localhost:8791/' <<<"$out" || fail "doctor did not name the running Board's address: $out"
  # Bug: doctor warned of a missing ast-grep that is in the virtualenv, or said nothing of it.
  grep -qx "ok: ast-grep, in the Board's virtualenv $XDG_DATA_HOME/conveyor/board-venv" <<<"$out" && ! grep -q '^warning: ast-grep' <<<"$out" \
    || fail "doctor did not name the installed ast-grep: $out"
  ! grep -q '^missing' <<<"$out" && grep -q '^ok: the pinned commit' <<<"$out" && grep -q '^ok: codex' <<<"$out" && grep -q '^ok: the terms file' <<<"$out" \
    && grep -q "^ok: segno, in the Board's virtualenv " <<<"$out" && ! grep -q 'no test times' <<<"$out" \
    && grep -qx 'ok: the plugin mattpocock-skills@claude-plugins-official, for /conveyor-belt:plan' <<<"$out" || fail "doctor with everything in place: $out"
  # Bug (#91), with both files there: setup prints an ok: line for each of CLAUDE.md and AGENTS.md, doctor the same
  # lines, and neither changes them.
  [ "$(agentlines "$said")" = "ok: CLAUDE.md, the project's instructions for Conveyor's Claude sessions (builder, fixer, Foreman, lanes)
ok: AGENTS.md, the project's instructions for the Codex reviewer" ] || fail "setup did not print an ok: line for each of CLAUDE.md and AGENTS.md: $said"
  [ "$(agentlines "$said")" = "$(agentlines "$out")" ] || fail "doctor did not print setup's lines for CLAUDE.md and AGENTS.md: setup: $said; doctor: $out"
  [ "$(cat "$S/CLAUDE.md")" = '# Sample' ] && [ "$(cat "$S/AGENTS.md")" = 'Read CLAUDE.md.' ] && [ -z "$(git -C "$S" status --porcelain -- CLAUDE.md AGENTS.md)" ] \
    || fail "setup or doctor changed CLAUDE.md or AGENTS.md"
}
# The project's card test lines, one for each jq object given, added to its test line (lib/views.sh UNTIMED), in the
# state folder of the sample (doctor's, as it runs in that checkout; state-dir alone names the plugin copy's).
doctortests() { # <jq object>...
  local s o; s=$(cd "$S" && CONVEYOR_MAIN=$S bash "$X" state-dir) && mkdir -p "$s" || fail "the state folder"
  # Whole records, as line() writes them: the snapshot doctor's Board check reads stops at any other line.
  for o in "$@"; do jq -cn "{card: \"c0-1\", issue: 1, step: \"test\", time: \"2026-11-01T00:00:00Z\", result: \"pass\", sha: \"\", reason: \"\", tokens: {claude: 0, codex: 0}} + $o"; done >> "$s/cards.jsonl"
}
# Bug caught (#515): a project's test command printed no `TESTRUN sec` lines, so none of its cards recorded test times,
# and doctor said nothing. Its last card test runs, a pass and a fail, recorded
# none (a later line of a batch that reused a run, and one that selected no file, are no run): doctor warns, naming
# the README section that says how to add them, and still passes.
t_doctoruntimed() {
  local X out; doctordone
  doctortests '{}' '{result: "fail"}' '{reused: true, times: null}' '{ended: "nothing selected"}'
  # Issue 346. Bug caught: a host file that still sets the removed machine room's settings (maxLoad, minFreeMemMB,
  # pressure) got no word that they no longer do anything, so its owner still thinks they hold cards back. Doctor
  # says so once, in one line naming each, and still passes. (In this case: doctor's warnings that do not fail it;
  # the one doctor run checks every warning.)
  # Issue 347. Bug caught: a host file that still sets the removed steer got no word that it does nothing, so its
  # owner still thinks card work yields to them. Doctor says so once, in one line.
  local H=$XDG_CONFIG_HOME/conveyor/host.json
  jq '.maxLoad = 2 | .minFreeMemMB = 1000 | .pressure = {strained: {cpu: 1}} | .steer = false' "$H" > "$T/$CASE/h" && mv "$T/$CASE/h" "$H" || fail "the host file was not rewritten"
  out=$(cd "$S" && bash "$X" doctor 2>&1) || fail "doctor failed over test times or the old machine-room settings: $out"
  grep -qxF 'warning: the last 2 card test runs recorded no test times: the test command prints no `TESTRUN sec` lines; conveyor/README.md, Test file times, says how to add them' <<<"$out" \
    || fail "doctor did not warn that the last card test runs recorded no test times: $out"
  [ "$(grep -c 'no longer do anything' <<<"$out")" = 1 ] \
    && grep -qxF "warning: the host file $H sets maxLoad, minFreeMemMB, pressure, which no longer do anything: no card or test waits for the machine's load, pressure or free memory; remove them" <<<"$out" \
    || fail "doctor did not say once that the old machine-room settings do nothing: $out"
  [ "$(grep -c 'steer' <<<"$out")" = 1 ] \
    && grep -qxF "warning: the host file $H sets steer, which no longer does anything: card sessions, reviews and test runs run at normal priority; remove it" <<<"$out" \
    || fail "doctor did not say once that the host file's steer does nothing: $out"
}
t_doctormissing() {
  local X out; doctordone
  # The owner's models.allowed names Codex models (a new pack names none, and follows the CLIs this host has), so the
  # reviewer is Codex's gpt-6.1-sol on a host with no Codex: the seat that cannot start (#593 below).
  jq '.models.allowed = {claude: ["claude-opus-5-5"], codex: ["gpt-6.1-sol"], "claude-reviewer": ["claude-opus-5-5"]}' "$S/.conveyor/project.json" > "$T/$CASE/p" \
    && mv "$T/$CASE/p" "$S/.conveyor/project.json" || fail "the pack was not rewritten"
  rm "$T/$CASE/terms" "$CLAUDE_CONFIG_DIR/plugins/installed_plugins.json" "$XDG_DATA_HOME/conveyor/board-venv/bin/ast-grep"; : > "$G/out"; uninstalled; echo segno > "$G/nopkg"
  local gone=d791d168d791d168d791d168d791d168d791d168; mkdir -p "$XDG_CONFIG_HOME/systemd/user" \
    && printf '[Service]\nExecStart="/bin/bash" "%s" serve\n' "$V/$gone/conveyor/conveyor.sh" > "$XDG_CONFIG_HOME/systemd/user/conveyor-gone-1.service"
  # The host file's one record is another checkout of the same folder name (setup adds no second record of a name).
  jq --arg m "$T/$CASE/other/sample" '.records = [{repo: "sample", main: $m}]' "$XDG_CONFIG_HOME/conveyor/host.json" > "$T/$CASE/h" \
    && mv "$T/$CASE/h" "$XDG_CONFIG_HOME/conveyor/host.json" || fail "the host file was not rewritten"
  # Nothing serves the Board's port: curl gets no page.
  mkdir -p "$T/$CASE/noboard" && printf '#!/bin/sh\nexit 7\n' > "$T/$CASE/noboard/curl" && chmod +x "$T/$CASE/noboard/curl" || fail "the curl stub was not made"
  # The control record setup wrote (t_setupheld), removed.
  local st; st=$(cd "$S" && CONVEYOR_MAIN=$S bash "$X" state-dir) && rm "$st/control.json" || fail "the control record was not removed"
  out=$(cd "$S" && PATH=$(PATH=$T/$CASE/noboard:$PATH without codex) bash "$X" doctor 2>&1) && fail "doctor passed with pieces missing: $out"
  # Bug (#111): with no control record the loop queues every open issue; doctor names it missing, so the service is
  # not offered before setup wrote it.
  grep -q "^missing: the control record $st/control.json .*; fix: run /conveyor-belt:setup" <<<"$out" || fail "doctor with no control record: $out"
  # Bug caught (#108): after setup no Board ran, and doctor said nothing of it. It names the Board as not running, at
  # its address, with the fix; a warning, as the Board is optional.
  grep -qxF 'warning: the Board is not running (nothing serves https://localhost:8790/); fix: run /conveyor-belt:setup and answer yes to "Start the Board now?", or conveyor.sh board in the project'"'"'s checkout' <<<"$out" \
    || fail "doctor did not name the Board as not running, with its fix: $out"
  # Bug caught (#17): the machine's Conveyor did not serve this checkout, as no record of the host file named it, and
  # doctor printed only "ok: the host file".
  grep -q "^missing: a record of the host file $XDG_CONFIG_HOME/conveyor/host.json for this checkout $S .*; fix: run /conveyor-belt:setup; .*add {\"repo\": \"<name>\", \"main\": \"$S\"}" <<<"$out" \
    || fail "doctor did not name the missing record of this checkout in the host file: $out"
  # Bug caught (#112): the Board cannot read the host file's one record (its checkout is not there), and doctor said
  # nothing, so every Board panel said it could not read. Doctor names it, with what the Board's read said.
  grep -qx "missing: the Board reading the project (.* answered, but its Conveyor gave no snapshot: .*$T/$CASE/other/sample.*); fix: correct the host file $XDG_CONFIG_HOME/conveyor/host.json as that says; .*" <<<"$out" \
    || fail "doctor did not name why the Board cannot read the host file's record: $out"
  grep -qx "missing: segno, for the Board, in its virtualenv $XDG_DATA_HOME/conveyor/board-venv; fix: run /conveyor-belt:setup, which installs it there" <<<"$out" \
    && grep -q "^ok: pyotp, in the Board's virtualenv " <<<"$out" || fail "doctor did not name the Board's missing package with its fix: $out"
  # Bug: with no ast-grep in the Board's virtualenv, doctor said nothing of it, or named it missing (a failure) when
  # it is optional. It warns, with the setup command that installs it.
  grep -qxF "warning: ast-grep is not in the Board's virtualenv $XDG_DATA_HOME/conveyor/board-venv, so sessions search code by text only; fix: run /conveyor-belt:setup, which installs it there" <<<"$out" \
    && ! grep -q '^missing: ast-grep' <<<"$out" || fail "doctor did not warn of the missing ast-grep with its fix: $out"
  rm "$G/nopkg"
  # Bug caught (#573): a service named an install that prune had removed, so a restart or a reboot would not start
  # its loop, and doctor said nothing.
  grep -qxF "missing: the file $V/$gone/conveyor/conveyor.sh that the service $XDG_CONFIG_HOME/systemd/user/conveyor-gone-1.service starts (a restart or a reboot does not start its loop); fix: run conveyor.sh install-service in the project's checkout, which writes the machine's service on an installed commit" <<<"$out" \
    || fail "doctor did not name a service whose conveyor.sh is gone, with that file: $out"
  grep -q '^missing: codex, .*; fix: install it (npm install -g @openai/codex)' <<<"$out" && grep -qx 'missing: gh signed in; fix: run /conveyor-belt:setup, which starts gh auth login' <<<"$out" \
    && grep -qx "missing: the install of the pinned commit $B; fix: run /conveyor-belt:setup, which installs it" <<<"$out" \
    && grep -q '^missing: a readable terms file .*; fix: make the file it names readable' <<<"$out" && grep -q '^ok: claude' <<<"$out" \
    && grep -qx 'missing: the plugin mattpocock-skills@claude-plugins-official, for /conveyor-belt:plan; fix: run claude plugin install mattpocock-skills@claude-plugins-official' <<<"$out" \
    || fail "doctor did not name each missing piece with its fix: $out" # the last: Matt Pocock's skills not installed
  # Bug caught (#593): the project has no control record, so its reviewer is the defaults' gpt-6.1-sol, a Codex
  # model; with no Codex here that seat cannot start, and doctor did not name the seat (only the CLI), or crashed.
  grep -qxF 'missing: a reviewer that can start (the reviewer is set to codex gpt-6.1-sol, and codex is not installed on this host (not on PATH)); fix: install its CLI, or set the reviewer to a CLI and model this host has (conveyor.sh control, or Rules on the Board)' <<<"$out" \
    && ! grep -q '^missing: a builder' <<<"$out" || fail "doctor did not name the reviewer seat that cannot start with no Codex, or named the builder: $out"
}
# A damaged version folder is refused by install, so a setup rerun alone cannot mend it: the fix removes it first,
# and the command doctor gives, then the install, leaves the pinned commit installed. Here it holds a folder and
# neither can be read or searched (mode 000), which a fix that only grants write could not empty. The command is the
# owner's to paste: it holds when the data folder has an apostrophe, as here and in t_doctorlink.
t_doctordamaged() {
  local X out l q="$T/$CASE/owner's-data" v; doctordone; v=$q/conveyor/versions/$B
  mkdir -p "$v/sub"; : > "$v/sub/f"; chmod 000 "$v/sub" "$v"; out=$(cd "$S" && XDG_DATA_HOME=$q bash "$X" doctor 2>&1)
  ! (cd "$S" && XDG_DATA_HOME=$q bash "$X" install "$B" >/dev/null 2>&1) || fail "install took a damaged version folder"
  l=$(grep "^missing: the install of the pinned commit $B (.*); fix: remove it (" <<<"$out") || fail "doctor gave no fix that removes a damaged install: $out"
  l=${l#*fix: remove it (}; eval "${l%%), then run /conveyor-belt:setup*}" && [ ! -e "$v" ] \
    || fail "doctor's removal did not remove the damaged install under a data folder with an apostrophe: $out"
  (cd "$S" && XDG_DATA_HOME=$q bash "$X" install "$B" >/dev/null 2>&1) && [ "$(git -C "$v" rev-parse HEAD)" = "$B" ] || fail "the install failed after doctor's fix"
}
# Bug: on Claude Code before 2.1.329 a card's guard hooks fail open (it ignores card-settings.json's "onFailure":
# "block"), and doctor said nothing. Doctor names it on 2.1.328 and says nothing of the guards on 2.1.330.
# On macOS doctor reads the claude first on PATH once Homebrew's bin is put first (p_path), so with the stub merely
# first on PATH a Mac with Claude Code in Homebrew's bin had its version read. The case makes the Homebrew prefix its
# own ($T/$CASE/brew: p_brewprefix takes it from the gtimeout first on PATH), with the real prefix's GNU and openssl
# folders under it, and puts the stub in its bin.
t_doctorguards() {
  local X out v pre d b=$T/$CASE/brew c=$T/$CASE/brew/bin/claude; doctordone; mkdir -p "$b/bin" "$b/opt"
  if p_darwin; then pre=$(p_brewprefix); ln -s "$pre/bin/gtimeout" "$b/bin/gtimeout" || fail "the Homebrew prefix was not made"
    for d in coreutils findutils gnu-sed grep openssl@3; do [ ! -d "$pre/opt/$d" ] || ln -s "$pre/opt/$d" "$b/opt/$d" || fail "the Homebrew prefix was not made"; done
  fi
  for v in 2.1.328 2.1.330; do
    # stub: the sample's claude ($G/claude) at the version under test, in the case's Homebrew bin; any other call goes to it.
    printf '#!/bin/sh\n[ "$1" != --version ] || { echo "%s (Claude Code)"; exit 0; }\nexec "%s" "$@"\n' "$v" "$G/claude" > "$c" && chmod +x "$c" || fail "the claude stub was not made"
    out=$(cd "$S" && PATH=$b/bin:$PATH bash "$X" doctor 2>&1)
    if [ $v = 2.1.328 ]; then
      grep -qxF "missing: Claude Code 2.1.329 or later for the card guards (found 2.1.328 at $c): card guards need 2.1.329 or later, as an older one lets a tool call through when a guard fails to run; fix: run $c update" <<<"$out" \
        || fail "doctor did not name 2.1.328 as too old for the card guards: $out"
    else ! grep -q 'card guards' <<<"$out" || fail "doctor named 2.1.330 as too old for the card guards: $out"; fi
  done
}
# The command removes a dangling link, which chmod cannot follow, as well as a damaged folder (t_doctordamaged).
t_doctorlink() {
  local X out l q="$T/$CASE/owner's-data"; doctordone
  mkdir -p "$q/conveyor/versions" && ln -s "$T/$CASE/nowhere" "$q/conveyor/versions/$B" || fail "the dangling link was not made"
  # #152. Bug: doctor's warning of untimed test runs did not say which runner setup found or which report option
  # gives the times. Checked in this case's doctor run, which the link does not change, to save a run of its own.
  doctortests '{}'
  jq '.test.report = {runner: "go test", option: "-json"}' "$S/.conveyor/project.json" > "$T/$CASE/p" && mv "$T/$CASE/p" "$S/.conveyor/project.json" || fail "the pack"
  out=$(cd "$S" && XDG_DATA_HOME=$q bash "$X" doctor 2>&1)
  grep -qxF 'warning: the last 1 card test run recorded no test times: the test command prints no `TESTRUN sec` lines; conveyor/README.md, Test file times, says how to add them; the test command runs go test, whose report option -json would give them' <<<"$out" \
    || fail "doctor did not name the runner and its report option: $out"
  l=$(grep "^missing: the install of the pinned commit $B (.*); fix: remove it (" <<<"$out") || fail "doctor gave no fix that removes a dangling link: $out"
  l=${l#*fix: remove it (}; eval "${l%%), then run /conveyor-belt:setup*}" && [ ! -e "$q/conveyor/versions/$B" ] && [ ! -L "$q/conveyor/versions/$B" ] \
    || fail "doctor's removal did not remove the dangling link under a data folder with an apostrophe: $out"
}
