#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: setup. (Doctor, and the CLAUDE.md and AGENTS.md lines: doctor.test.sh.)
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# A sample project with no Conveyor in it, $S, with a CLAUDE.md and an AGENTS.md, on a feature branch, whose origin's default branch is trunk (with no
# refs/remotes/origin/HEAD to say so), beside the code repo ($D, the plugin copy at commit $B), and a gh,
# claude, codex and opencode stubbed in $G: gh's labels are $G/labels, those it created $G/created; it is signed out while
# $G/out is there. Like GitHub, it lists every label (no first page only) and refuses to create one the repo has
# under any case. The case's own host file names a readable terms file. All but the host file is made once per run
# (samplemake, lib.sh template) and copied.
sample() {
  coderepo; trap 'chmod -R u+w "$T/$CASE"' EXIT
  # CLAUDE_CONFIG_DIR: Claude Code's folder, where its record of installed plugins is, the case's own (empty).
  export S=$T/$CASE/sample G=$T/$CASE/gh XDG_CONFIG_HOME=$T/$CASE/config CLAUDE_CONFIG_DIR=$T/$CASE/claude
  # The Board's login store, the case's own: its certificate is beside it (boardup), never in ~/.claude/rulings.
  export CONVEYOR_DASHBOARD_AUTH=$T/$CASE/rulings/dashboard-auth.json
  template sample samplemake && mkdir -p "$XDG_CONFIG_HOME/conveyor" "$XDG_DATA_HOME/conveyor" && cp -a "$FIXTURE.sample/sample" "$S" \
    && cp -a "$FIXTURE.sample/origin.git" "$T/$CASE/origin.git" && git -C "$S" remote set-url origin "$T/$CASE/origin.git" \
    && cp -a "$FIXTURE.sample/gh" "$G" && cp -a "$FIXTURE.sample/board-venv" "$XDG_DATA_HOME/conveyor/board-venv" \
    || fail "the sample repo was not made"
  # The plugin's one release, v1.0.0, is the plugin copy's commit $B (gh lists $G/releases).
  git -C "$D" tag v1.0.0 "$B" && git -C "$D" push -q origin v1.0.0 && echo '[{"tagName":"v1.0.0","isDraft":false,"isPrerelease":false}]' > "$G/releases" \
    || fail "the plugin's release was not made"
  PATH=$G:$PATH
  # The machine's host file, with each CLI's route already set to its own login, as an earlier setup writes it: a case
  # of the route questions (t_setupproxy, t_apisetup) takes them out.
  echo 'case:Zed' > "$T/$CASE/terms"
  jq -n --arg t "$T/$CASE/terms" '{terms: $t, claudeProxy: {kind: "subscription"}, codexProxy: {kind: "subscription"}}' > "$XDG_CONFIG_HOME/conveyor/host.json"
}
samplemake() { # <folder>: what sample copies, in <folder>: sample, origin.git, gh (G) and board-venv
  local S=$1/sample G=$1/gh
  mkdir -p "$S" "$G" "$1/board-venv/bin" && git -C "$S" init -q -b feature \
    && git init -q --bare -b trunk "$1/origin.git" && git -C "$S" remote add origin "$1/origin.git" \
    && echo '# Sample' > "$S/CLAUDE.md" && echo 'Read CLAUDE.md.' > "$S/AGENTS.md" && echo true > "$S/a.test.sh" && git -C "$S" add CLAUDE.md AGENTS.md a.test.sh \
    && git -C "$S" -c user.name=t -c user.email=t${AT}example.com commit -q -m one && git -C "$S" push -q origin feature:trunk \
    || return 1
  printf '%s\n' Bug Feature > "$G/labels"
  cat > "$G/gh" <<'EOF'
#!/usr/bin/env bash
case "$1 $2" in
  "label list") [ "$*" = "label list --limit 10000 --json name --jq .[].name" ] && cat "$G/labels" ;;
  "label create") # like gh, a name before -- that starts with - is a flag: --help prints help, exits 0, creates nothing
    if [ "$3" = -- ]; then n=$4; elif [[ $3 == -* ]]; then exit 0; else n=$3; fi
    ! grep -qixF -- "$n" "$G/labels" && echo "$n" >> "$G/labels" && echo "$n" >> "$G/created" ;;
  "auth status") [ ! -e "$G/out" ] ;;
  "release list") cat "$G/releases" ;;
  "issue list") # $G/issues: the repo's issues, a JSON list of {number, state} (none: no issues); --state all: the newest
    i=$(cat "$G/issues" 2>/dev/null || echo '[]')
    if [[ " $* " == *" --state all --limit 1 "* ]]; then jq -c 'sort_by(-.number) | .[:1] | map({number})' <<<"$i"
    elif [[ " $* " == *" --state open "* ]]; then jq -c 'map(select(.state == "open") | {number})' <<<"$i"; else exit 1; fi ;;
  "issue create") # each issue filed, its arguments as a JSON list a line in $G/filed, numbered from 101
    printf '%s\0' "${@:3}" | jq -cRs 'split("\u0000")[:-1]' >> "$G/filed" && echo "https://github.com/example/sample/issues/$((100 + $(wc -l < "$G/filed")))" ;;
  *) exit 1 ;;
esac
EOF
  # claude: `plugin install <plugin>` records it in $G/claude-installs and, as Claude Code does, in its record of
  # installed plugins in CLAUDE_CONFIG_DIR; --version is a version doctor takes (2.1.322 or newer); a call with no
  # tools (doctor's askcheck()) answers $G/ask, else OK, in Claude's JSON (with no --output-format json, as Claude
  # Code does, only its result); anything else does nothing.
  cat > "$G/claude" <<'EOF'
#!/usr/bin/env bash
[ "$1" != --version ] || { echo '2.1.400 (Claude Code)'; exit 0; }
case " $* " in *" --tools  "*) cat > /dev/null; j=$(cat "$G/ask" 2>/dev/null || echo '{"type":"result","is_error":false,"subtype":"success","result":"OK","num_turns":1}')
  [[ " $* " == *" --output-format json "* ]] && echo "$j" || jq -r .result <<<"$j"; exit 0 ;; esac
[ "$1 $2" = "plugin install" ] || exit 0
mkdir -p "$CLAUDE_CONFIG_DIR/plugins" && echo "$3" >> "$G/claude-installs" \
  && jq -n --arg p "$3" '{version: 2, plugins: {($p): [{scope: "user"}]}}' > "$CLAUDE_CONFIG_DIR/plugins/installed_plugins.json"
EOF
  printf '#!/bin/sh\n' > "$G/codex"
  # An OpenCode that lists no models: the host's own, found otherwise, is asked `opencode models` by doctor and the
  # Board's check (hostclis), and can take its whole 20 s timeout to answer.
  printf '#!/bin/sh\nexit 1\n' > "$G/opencode"; chmod +x "$G/gh" "$G/claude" "$G/codex" "$G/opencode" || return 1
  # The Board's virtualenv, already made: its python3 records each pip call in $G/pip and, as pip with
  # --require-hashes does, fails unless the file it is given pins each package the Board imports, with a hash; it
  # fails to import the package $G/nopkg names.
  cat > "$1/board-venv/bin/python3" <<'EOF'
#!/usr/bin/env bash
[ "$1 $2" != "-m pip" ] || { echo "$*" >> "$G/pip"; r=${*: -1}
  for p in pyotp segno cryptography; do grep -A1 "^$p==" "$r" | grep -q -- '--hash=sha256:' || exit 1; done; exit 0; }
[ ! -s "$G/nopkg" ] || [ "$*" != "-c import $(cat "$G/nopkg")" ]
EOF
  chmod +x "$1/board-venv/bin/python3"
}
# What setup may change, as it stands: the pack, the installs and the repo's labels.
setupstate() { cat "$S/.conveyor/project.json" "$G/labels"; find "$V" -printf '%p %m\n' | sort; }

# Bugs: setup from nothing asks for what has a safe default, or writes a pack that fails the check, or leaves the
# project following no main (or, with --pin, with no pin), no engine installed, or without a label its pack names; it writes half a pack when an answer is
# missing; a rerun changes the pack, the pin, the install or the labels; a pin already there is replaced; a label the
# repo has under other case, or two the pack names that differ only in case, are created twice.
t_setup() {
  sample; local X=$D/conveyor/conveyor.sh out was
  out=$(cd "$S" && bash "$X" setup 2>&1); [ $? = 2 ] || fail "setup with no pack and no answers did not exit 2: $out"
  grep -q -- '--owner' <<<"$out" && grep -q -- '--product' <<<"$out" && grep -q -- '--test' <<<"$out" \
    && grep -q -- '--fast-lane <yes or no' <<<"$out" && grep -q -- '--research-lane <yes or no' <<<"$out" \
    && grep -qF -- '--survey <yes or no: run a first test-speed survey now?>' <<<"$out" || fail "setup did not name each answer it needs: $out"
  ! grep -qE -- '--(remote|branch|label|model)' <<<"$out" || fail "setup asked for what has a safe default: $out"
  out=$(cd "$S" && bash "$X" setup --fast-lane no --research-lane no --owner Dana --product src/ --survey no 2>&1); [ $? = 2 ] && grep -q -- '--test' <<<"$out" && ! grep -q -- '--owner' <<<"$out" \
    || fail "setup with the test command missing did not ask for it alone: $out"
  [ ! -e "$S/.conveyor" ] && [ ! -e "$V" ] && [ ! -e "$G/created" ] && [ ! -e "$G/pip" ] || fail "setup with an answer missing wrote something"
  # Origin's default branch is the landing and push target; when it cannot be read, the checked-out branch is no stand-in.
  git -C "$S" remote set-url origin "$T/$CASE/none.git"
  out=$(cd "$S" && bash "$X" setup --fast-lane no --research-lane no --owner Dana --product src/ --test t --survey no 2>&1) && fail "setup went on with origin's default branch unread: $out"
  grep -q "origin's default branch could not be read" <<<"$out" && [ ! -e "$S/.conveyor" ] && [ ! -e "$V" ] || fail "setup with origin unread: $out"
  git -C "$S" remote set-url origin "$T/$CASE/origin.git"
  out=$(cd "$S" && bash "$X" setup --fast-lane no --research-lane no --owner Dana --product src/ --product 'web app/' --test 'npm test' --survey no 2>&1) || fail "setup from nothing exited non-zero: $out"
  # Bug: a new install lands cards and pushes none (the push rule is off by default), and setup did not say so, so
  # the owner waited for pushes that never came. Its last line names Push landed and the Rules tab.
  [ "$(tail -n 1 <<<"$out")" = 'conveyor: landed cards wait for Push landed on the Board until push is turned on in the Rules tab' ] \
    || fail "setup's last line does not say that landed cards wait for Push landed: $out"
  bash "$SRC/lib/pack.sh" check "$S/.conveyor/project.json" || fail "setup wrote a pack that fails the check"
  # Bug: a new project follows the plugin's main, where changes are tested before they are released. It follows the
  # plugin's releases, and its newest release (v1.0.0, $B) is taken and installed. Bug: a new pack named no test.full,
  # so the Push landed its last line sends the owner to was greyed and `full-test push` refused: the test command is it.
  jq -e '.owner.name == "Dana" and .productPaths == ["src/", "web app/"] and .test.command == "npm test" and .test.full == "npm test" and .defaultBranch == "trunk"
      and .plugin == {follow: "releases"} and .privacy.mode == "public" and .remote == "origin"' "$S/.conveyor/project.json" >/dev/null \
    || fail "the pack is not the answers, the defaults and the plugin's releases followed: $(cat "$S/.conveyor/project.json")"
  # Bug: a new pack turned on a standing kind of routine yes the owner never chose; each is off until they turn it on.
  jq -e '.auto.standing == []' "$S/.conveyor/project.json" >/dev/null || fail "setup did not write auto.standing empty: $(jq -c .auto "$S/.conveyor/project.json")"
  # No to the first test-speed survey: none filed, and the answer saved, so the rerun below is not asked again.
  [ ! -e "$G/filed" ] && jq -e '.test.firstSurvey == false' "$S/.conveyor/project.json" >/dev/null \
    || fail "setup --survey no filed a survey issue, or did not save the answer: $(cat "$G/filed" 2>&1) $(jq -c .test "$S/.conveyor/project.json")"
  [ "$(jq -r '"\(.commit) \(.release)"' "$S/.git/conveyor-engine.json")" = "$B v1.0.0" ] || fail "setup did not take the plugin's release: $(cat "$S/.git/conveyor-engine.json")"
  [ "$(git -C "$V/$B" rev-parse HEAD)" = "$B" ] && [ -z "$(find "$V/$B" ! -type l -perm /222)" ] || fail "the commit taken, $B, is not installed read-only"
  [ "$(sort "$G/created" | tr '\n' ' ')" = 'P0 P1 P2 awaiting-deploy conveyor-followup ' ] || fail "the labels created: $(cat "$G/created")"
  # The Board's packages go into its own virtualenv, from the pinned file, every hash checked.
  grep -qxE -- "-m pip install -q --require-hashes -r .*/\.claude/scripts/requirements\.txt" "$G/pip" || fail "setup did not fill the Board's virtualenv with hashes checked: $(cat "$G/pip" 2>&1)"
  [ ! -e "$S/conveyor/state/cards.jsonl" ] || fail "setup made a state folder"
  # Bug caught (#17): the default state folder showed as untracked in the project, so `git add -A` committed it.
  mkdir -p "$S/conveyor/state" && echo '{}' > "$S/conveyor/state/cards.jsonl" \
    && [ -z "$(git -C "$S" status --porcelain --untracked-files=all -- conveyor/state)" ] || fail "git status lists the state folder after setup: $(git -C "$S" status --porcelain -- conveyor/state)"
  rm "$S/conveyor/state/cards.jsonl"
  # Bug: Matt Pocock's skills, which /conveyor-belt:plan reads, were left uninstalled: setup installs them from the
  # official marketplace once, and a rerun, finding them installed, does not install them again.
  [ "$(cat "$G/claude-installs" 2>&1)" = mattpocock-skills@claude-plugins-official ] || fail "setup did not install mattpocock-skills: $(cat "$G/claude-installs" 2>&1)"
  was=$(setupstate); out=$(cd "$S" && bash "$X" setup --fast-lane no --research-lane no 2>&1) || fail "setup run again exited non-zero: $out"
  [ "$(setupstate)" = "$was" ] && [ "$(wc -l < "$G/created")" = 5 ] && [ "$(wc -l < "$G/claude-installs")" = 1 ] || fail "setup run again changed something: $(diff <(echo "$was") <(setupstate)) $(cat "$G/claude-installs")"
  ! grep -qE 'wrote|pinned|follows|created' <<<"$out" || fail "setup run again says it changed something: $out"
}
# The cases below go on from a project setup made (setupdone): one after another, they and the case above made one case of 5 s.
setupdone() { sample; X=$D/conveyor/conveyor.sh; (cd "$S" && bash "$X" setup --fast-lane no --research-lane no --owner Dana --product src/ --test t --survey no >/dev/null) || fail "setup from nothing exited non-zero"; }
t_setuppin() {
  local X out; setupdone
  # With --pin, a pack naming no plugin pins the plugin copy's commit instead.
  # Bug: on a pack already there with no test.full, setup's last line sent the owner to a Push landed that is greyed
  # (fulltest() refuses with no test.full): it says the pack needs one.
  jq 'del(.plugin, .test.full)' "$S/.conveyor/project.json" > "$T/$CASE/p" && mv "$T/$CASE/p" "$S/.conveyor/project.json"
  out=$(cd "$S" && bash "$X" setup --fast-lane no --research-lane no --pin 2>&1) || fail "setup --pin exited non-zero: $out"
  [ "$(jq -c .plugin "$S/.conveyor/project.json")" = "{\"commit\":\"$B\"}" ] && grep -q "pinned Conveyor commit $B" <<<"$out" || fail "setup --pin did not pin the plugin copy's commit: $out"
  [ "$(tail -n 1 <<<"$out")" = "conveyor: landed cards wait for Push landed on the Board until push is turned on in the Rules tab; Push landed needs the pack's test.full, the full test suite: add it" ] \
    || fail "setup on a pack with no test.full did not say Push landed needs one: $out"
  # A pin already there is kept, and its commit installed.
  jq --arg a "$A" '.plugin = {commit: $a}' "$S/.conveyor/project.json" > "$T/$CASE/p" && mv "$T/$CASE/p" "$S/.conveyor/project.json"
  (cd "$S" && bash "$X" setup --fast-lane no --research-lane no >/dev/null) || fail "setup with a pin already there exited non-zero"
  [ "$(jq -r .plugin.commit "$S/.conveyor/project.json")" = "$A" ] && [ "$(git -C "$V/$A" rev-parse HEAD)" = "$A" ] || fail "setup replaced a pin, or did not install it"
  # Bug: setup moves a project that follows main (the owner's own, to run each change before it is released) to releases.
  jq '.plugin = {follow: "main"}' "$S/.conveyor/project.json" > "$T/$CASE/p" && mv "$T/$CASE/p" "$S/.conveyor/project.json"
  out=$(cd "$S" && bash "$X" setup --fast-lane no --research-lane no 2>&1) || fail "setup on a project that follows main exited non-zero: $out"
  [ "$(jq -c .plugin "$S/.conveyor/project.json")" = '{"follow":"main"}' ] || fail "setup changed a project that follows main: $(jq -c .plugin "$S/.conveyor/project.json")"
}
t_setuplabels() {
  local X out; setupdone
  # Two labels the pack names that differ only in case are one label on GitHub: created once.
  jq '.labels.built = "Shipped" | .labels.followup = "shipped"' "$S/.conveyor/project.json" > "$T/$CASE/p" && mv "$T/$CASE/p" "$S/.conveyor/project.json"
  out=$(cd "$S" && bash "$X" setup --fast-lane no --research-lane no 2>&1) || fail "setup with labels that differ only in case exited non-zero: $out"
  [ "$(grep -ci '^shipped$' "$G/created")" = 1 ] || fail "a label was created once for each case: $(cat "$G/created")"
  # A label named like a flag is still the label's name: created, not read by gh as an option (--help exits 0 and creates nothing).
  jq '.labels.built = "--help"' "$S/.conveyor/project.json" > "$T/$CASE/p" && mv "$T/$CASE/p" "$S/.conveyor/project.json"
  out=$(cd "$S" && bash "$X" setup --fast-lane no --research-lane no 2>&1) || fail "setup with a label named --help exited non-zero: $out"
  grep -qxF -- --help "$G/created" || fail "setup said it created the label --help but did not: $out"
  # Nor does the privacy check read a name after -- as an option: --input=missing is a name, not a file to read.
  jq '.labels.built = "--input=missing"' "$S/.conveyor/project.json" > "$T/$CASE/p" && mv "$T/$CASE/p" "$S/.conveyor/project.json"
  out=$(cd "$S" && bash "$X" setup --fast-lane no --research-lane no 2>&1) || fail "setup with a label named --input=missing exited non-zero: $out"
  grep -qxF -- --input=missing "$G/created" || fail "the label --input=missing was not created: $out"
}
t_setupbad() {
  local X was; setupdone
  # A pack that fails the check is not rewritten, and nothing is installed or created for it.
  jq '.owner.name = ""' "$S/.conveyor/project.json" > "$T/$CASE/p" && mv "$T/$CASE/p" "$S/.conveyor/project.json"; was=$(setupstate)
  (cd "$S" && bash "$X" setup --fast-lane no --research-lane no --owner Robin --product x/ --test t --survey no >/dev/null 2>&1) && fail "setup went on with a pack that fails the check"
  [ "$(setupstate)" = "$was" ] || fail "setup changed a project whose pack fails the check"
}
# Bug caught (#515): a project whose test command runs its own shell script, one test file after another, printing no
# `TESTRUN sec` lines, recorded no test times on any card, and setup never said so. Setup names the script (here the
# word `scripts/test.sh;`, the end of the command's first part) and shows
# how to wrap each file's run with tools/testtime.sh, changing no line of the script; a script that uses the helper
# hears nothing. Its new pack has test.slowIssues false, and the test rules' switch off with no rule on.
t_setuptiming() {
  local X out; sample; X=$D/conveyor/conveyor.sh
  mkdir -p "$S/scripts" && printf '#!/bin/sh\nfor f in tests/*.sh; do echo "== $f" >> "$CONVEYOR_TEST_LOG/run.log"; sh "$f"; done\n' > "$S/scripts/test.sh"
  cp "$S/scripts/test.sh" "$T/$CASE/script.was"
  out=$(cd "$S" && bash "$X" setup --fast-lane no --research-lane no --owner Dana --product src/ --test 'bash scripts/test.sh; true' --survey no 2>&1) || fail "setup exited non-zero: $out"
  grep -qF 'conveyor: the test command runs scripts/test.sh, which prints no `TESTRUN sec` lines, so cards record no test times.' <<<"$out" \
    && grep -qF "copy $D/conveyor/tools/testtime.sh into the project" <<<"$out" && grep -qF './testtime.sh "$f" -- <the file'"'"'s command>' <<<"$out" \
    && grep -qF 'conveyor/README.md, Test file times' <<<"$out" || fail "setup did not say how to wrap each test file's run: $out"
  cmp -s "$S/scripts/test.sh" "$T/$CASE/script.was" || fail "setup changed the project's test script"
  jq -e '.test.slowIssues == false' "$S/.conveyor/project.json" > /dev/null || fail "setup's new pack does not turn Slow test issues off: $(jq -c .test "$S/.conveyor/project.json")"
  # Issue 519: a new install starts with the test rules' switch off and no rule on (a pack that names no switch is off: testrules.test.sh).
  jq -e '(.test.rules.on // false) == false and ([.test.rules.list[]? | select(.on)] == [])' "$S/.conveyor/project.json" > /dev/null \
    || fail "setup's new pack has the test rules on: $(jq -c .test.rules "$S/.conveyor/project.json")"
  sed -i 's/sh "$f"/.\/testtime.sh "$f" -- sh "$f"/' "$S/scripts/test.sh"
  out=$(cd "$S" && bash "$X" setup --fast-lane no --research-lane no 2>&1) || fail "setup run again exited non-zero: $out"
  ! grep -q 'TESTRUN sec' <<<"$out" || fail "setup said a script that uses testtime.sh records no times: $out"
}
# The first test-speed survey (lib/survey.sh, firstsurvey()). Bugs: yes files no survey issue, or two, or one of
# another kind than the monthly one (pick takes that kind only in the quiet hour), or one whose card is not asked for
# the shared helpers; the answer is not saved, so every setup run asks again and a yes
# files again; --survey cannot ask for another later.
t_setupsurvey() {
  local X out; sample; X=$D/conveyor/conveyor.sh
  out=$(cd "$S" && bash "$X" setup --fast-lane no --research-lane no --owner Dana --product src/ --test t --survey yes 2>&1) || fail "setup --survey yes exited non-zero: $out"
  [ "$(jq -c '[.[1], .[3], .[5]]' "$G/filed")" = '["Test-speed survey, first","bug","P1"]' ] && grep -q '^conveyor: filed #101, Test-speed survey, first$' <<<"$out" \
    && jq -e '.test.firstSurvey == true' "$S/.conveyor/project.json" >/dev/null \
    || fail "setup --survey yes did not file exactly one first survey issue of the monthly kind, or did not save the answer: $(cat "$G/filed" 2>&1) $out"
  jq -e '.[7] | contains("each of the project'"'"'s test files alone") and contains("clock seconds") and contains("CPU seconds")
      and (contains("budget") | not)
      and contains("each shared helper the measurements point to") and contains("for the Foreman to file as cards")' "$G/filed" >/dev/null \
    || fail "the first survey's issue does not ask for each file alone and the shared helpers, or names a CPU budget no file has (#349): $(jq -r '.[7]' "$G/filed")"
  out=$(cd "$S" && bash "$X" setup --fast-lane no --research-lane no 2>&1) && [ "$(wc -l < "$G/filed")" = 1 ] || fail "setup run again asked again, or filed again: $out"
  out=$(cd "$S" && bash "$X" setup --fast-lane no --research-lane no --survey yes 2>&1) && [ "$(wc -l < "$G/filed")" = 2 ] && grep -q 'filed #102' <<<"$out" \
    || fail "setup --survey yes run again did not file another survey: $out"
}
# A project set up before the question (its pack has no answer) is asked it, with nothing changed until it answers;
# no then files none and saves the answer. An answer that is neither yes nor no is refused.
t_setupasked() {
  local X out was; setupdone
  jq 'del(.test.firstSurvey)' "$S/.conveyor/project.json" > "$T/$CASE/p" && mv "$T/$CASE/p" "$S/.conveyor/project.json"; was=$(setupstate)
  out=$(cd "$S" && bash "$X" setup --fast-lane no --research-lane no 2>&1); [ $? = 2 ] && grep -qF 'setup needs: --survey <yes or no: run a first test-speed survey now?>' <<<"$out" \
    && [ "$(setupstate)" = "$was" ] || fail "setup with no saved answer did not ask the question before changing anything: $out"
  out=$(cd "$S" && bash "$X" setup --fast-lane no --research-lane no --survey maybe 2>&1); [ $? = 2 ] && grep -q '^usage: .*--survey yes|no' <<<"$out" || fail "setup took --survey maybe: $out"
  out=$(cd "$S" && bash "$X" setup --fast-lane no --research-lane no --survey no 2>&1) && [ ! -e "$G/filed" ] && jq -e '.test.firstSurvey == false' "$S/.conveyor/project.json" >/dev/null \
    || fail "setup --survey no filed a survey issue, or did not save the answer: $out $(cat "$G/filed" 2>&1)"
}
# #137. Bug: setup left a project whose test files the default misses (src/test-a.js, src/test-b.js) with no
# tests.patterns, so its bug cards found no test file. It asks before changing anything, showing the globs and the
# tracked files they match; yes writes them as the pack's tests.patterns.
t_setuptestpatterns() {
  local X out was; setupdone
  mkdir -p "$S/src" && echo x > "$S/src/test-a.js" && echo x > "$S/src/test-b.js" && git -C "$S" add src && git -C "$S" -c user.name=t -c user.email=t${AT}example.com commit -qm tests || fail "the test files"
  was=$(setupstate); out=$(cd "$S" && bash "$X" setup --fast-lane no --research-lane no 2>&1); [ $? = 2 ] && [ "$(setupstate)" = "$was" ] \
    && grep -qF -- '--test-patterns <yes or no: the default test-file patterns miss 2 tracked files that read as tests; set the pack'"'"'s tests.patterns to __tests__/ (0 tracked files), ' <<<"$out" \
    && grep -qF -- 't/*.sh (0 tracked files), test-*.js (2 tracked files, by the names of tracked files), which match 3 tracked files?>' <<<"$out" || fail "setup did not ask for the patterns it found, before changing anything: $out"
  out=$(cd "$S" && bash "$X" setup --fast-lane no --research-lane no --test-patterns yes 2>&1) && jq -e '.tests.patterns[-1] == "test-*.js"' "$S/.conveyor/project.json" >/dev/null \
    || fail "setup --test-patterns yes did not write the patterns: $out"
}
# #1050. Bug: a project whose Jest testMatch names its test files (checks/*.check.js, which neither the default nor a
# test word in their names finds) got no tests.patterns from setup. It asks before changing anything, naming the
# testMatch glob, its count and where it was read; no writes nothing, yes writes that glob (and *.test.sh, the guess
# from the name of the sample's own test file, which the testMatch misses).
t_setupjestmatch() {
  local X out was; setupdone
  mkdir -p "$S/checks" && echo x > "$S/checks/a.check.js" && echo x > "$S/checks/b.check.js" \
    && echo '{"jest": {"testMatch": ["<rootDir>/checks/*.check.js"]}}' > "$S/package.json" \
    && git -C "$S" add checks package.json && git -C "$S" -c user.name=t -c user.email=t${AT}example.com commit -qm tests || fail "the test files"
  was=$(setupstate); out=$(cd "$S" && bash "$X" setup --fast-lane no --research-lane no 2>&1); [ $? = 2 ] && [ "$(setupstate)" = "$was" ] \
    && grep -qF -- "--test-patterns <yes or no: the test command and its runner's config name the project's test files; set the pack's tests.patterns to /checks/*.check.js (2 tracked files, from Jest testMatch in package.json)" <<<"$out" \
    || fail "setup did not ask for the Jest testMatch glob with its count, before changing anything: $out"
  # The package.json makes setup ask for the test map too (V8 coverage): answered no, as it is no part of this case.
  out=$(cd "$S" && bash "$X" setup --fast-lane no --research-lane no --test-map no --test-patterns no 2>&1) && ! jq -e '.tests.patterns' "$S/.conveyor/project.json" >/dev/null \
    || fail "setup --test-patterns no wrote the patterns: $out"
  out=$(cd "$S" && bash "$X" setup --fast-lane no --research-lane no --test-map no --test-patterns yes 2>&1) && jq -e '.tests.patterns == ["/checks/*.check.js", "*.test.sh"]' "$S/.conveyor/project.json" >/dev/null \
    || fail "setup --test-patterns yes did not write the Jest testMatch glob: $out"
}
# #147. Bug: a project whose test command is a plain `npm test` (here jest, by its package.json script) ran its whole
# suite on every card, and setup did not say the command could run one test file. It names the runner and asks before
# changing anything; yes writes the test command as test.fileCommand, which a card runs each test file with (#374: the
# question offered test.list, which no card's run reads, and the cards stopped at their test step).
t_setuptestlist() {
  local X out was; setupdone
  echo '{"scripts": {"test": "jest --ci"}}' > "$S/package.json"
  jq '.test.command = "npm test"' "$S/.conveyor/project.json" > "$T/$CASE/p" && mv "$T/$CASE/p" "$S/.conveyor/project.json"
  was=$(setupstate); out=$(cd "$S" && bash "$X" setup --fast-lane no --research-lane no 2>&1); [ $? = 2 ] && [ "$(setupstate)" = "$was" ] \
    && grep -qF -- "--file-command <yes or no: the test command runs jest, which takes test files as arguments; set the pack's test.fileCommand to the test command," <<<"$out" \
    || fail "setup did not ask to set test.fileCommand for jest before changing anything: $out"
  # #709. Bug: commands/setup.md listed --file-command but not its question, so the session had nothing to ask. The
  # file is instructions to a Claude session and cannot run here, so the case reads its text.
  tr -s ' \n' '  ' < "$SRC/../commands/setup.md" | grep -qF "\"Set the pack's test.fileCommand to the test command, so a card runs each of its test files alone through it?\" (yes / no)" \
    || fail "commands/setup.md does not give the question to ask for --file-command"
  out=$(cd "$S" && bash "$X" setup --fast-lane no --research-lane no --file-command yes --test-map no 2>&1) && jq -e '.test.fileCommand == "npm test"' "$S/.conveyor/project.json" >/dev/null \
    || fail "setup --file-command yes did not write test.fileCommand: $out"
  # #152. Bug: setup did not find how to read the runner's report, so no card recorded test times unless the owner
  # changed the test command. Jest (an npm script) with no report option: the pack's test.report has Conveyor add the
  # option after `--` at each run, and setup says so.
  jq -e '.test.report == {runner: "jest", format: "jest-json", args: "-- --json --outputFile=<file>"}' "$S/.conveyor/project.json" >/dev/null \
    && grep -qF "conveyor: wrote the pack's test.report: the test command runs jest, and Conveyor reads each test file's clock seconds from its report (jest-json, which Conveyor asks it for at each run)" <<<"$out" \
    || fail "setup did not write the pack's test.report for jest: $(jq -c .test.report "$S/.conveyor/project.json") $out"
}
# #150. Bug: a new install had no test map, so a card's tests were only guessed by name. Setup of a Node project asks
# before the whole suite runs under coverage, naming the tool and its cost; no writes test.map off; yes makes the map,
# which sends src/a.js to test/a.test.js alone, and says what it mapped and how long it took.
t_setuptestmap() {
  local X out was; setupdone
  mkdir -p "$S/src" "$S/test" && echo '{}' > "$S/package.json" && echo 'module.exports = 1;' > "$S/src/a.js" && echo 'module.exports = 2;' > "$S/src/b.js" \
    && echo "require('../src/a.js');" > "$S/test/a.test.js" && echo "require('../src/b.js');" > "$S/test/b.test.js" \
    && git -C "$S" add -A && git -C "$S" -c user.name=t -c user.email=t${AT}example.com commit -qm node || fail "the Node files"
  was=$(setupstate); out=$(cd "$S" && bash "$X" setup --fast-lane no --research-lane no 2>&1); [ $? = 2 ] && [ "$(setupstate)" = "$was" ] && [ ! -e "$S/.conveyor/test-map.json" ] \
    && grep -qF -- "--test-map <yes or no: run the whole suite once with V8 coverage to make the test map (which test files cover which source files), so a card runs only the tests that cover its change? Its time is not known (no whole-suite run is recorded)" <<<"$out" \
    || fail "setup did not ask before making the test map: $out"
  out=$(cd "$S" && bash "$X" setup --fast-lane no --research-lane no --test-map no 2>&1) && jq -e '.test.map == "off"' "$S/.conveyor/project.json" >/dev/null \
    || fail "setup --test-map no did not write test.map off: $out"
  jq 'del(.test.map)' "$S/.conveyor/project.json" > "$T/$CASE/p" && mv "$T/$CASE/p" "$S/.conveyor/project.json" || fail "the pack"
  out=$(cd "$S" && bash "$X" setup --fast-lane no --research-lane no --test-map yes 2>&1) \
    && grep -qE '^conveyor: wrote the test map .*/test-map\.json with V8 coverage: 2 source files, 2 test files, in [0-9]+s$' <<<"$out" \
    && jq -e '.sources["src/a.js"] == ["test/a.test.js"]' "$S/.conveyor/test-map.json" >/dev/null || fail "setup --test-map yes did not make the map: $out"
}
# Bug: setup made no lane, so the owner had to know to run `lane fast create` and `lane research create` by hand. It
# asks for both on every run, before it changes anything, and no to both makes neither.
t_setuplaneasked() {
  local X out was; setupdone
  [ "$(git -C "$S" worktree list | wc -l)" = 1 ] && [ ! -e "$S-fast-lane" ] && [ ! -e "$S-research" ] \
    || fail "setup with no to both lanes made a lane: $(git -C "$S" worktree list)"
  was=$(setupstate)
  out=$(cd "$S" && bash "$X" setup --research-lane no 2>&1); [ $? = 2 ] && grep -qF -- '--fast-lane <yes or no' <<<"$out" && ! grep -q -- '--research-lane' <<<"$out" \
    && [ "$(setupstate)" = "$was" ] || fail "setup with no --fast-lane did not ask for it alone before changing anything: $out"
  out=$(cd "$S" && bash "$X" setup --fast-lane no 2>&1); [ $? = 2 ] && grep -qF -- '--research-lane <yes or no' <<<"$out" && ! grep -q -- '--fast-lane' <<<"$out" \
    && [ "$(setupstate)" = "$was" ] || fail "setup with no --research-lane did not ask for it alone before changing anything: $out"
  out=$(cd "$S" && bash "$X" setup --fast-lane maybe --research-lane no 2>&1); [ $? = 2 ] && grep -q '^usage: .*--fast-lane yes|no' <<<"$out" || fail "setup took --fast-lane maybe: $out"
}
# Bug: yes to a lane left it unmade, or made it otherwise than its own create does; run again, setup failed on a lane
# that is there, or changed it. The sandbox is stubbed (bwrap, sandbox-exec run the command they are given): the
# lane's own tests (lanes/research.test.sh) prove the real one.
lanestubs() {
  printf '#!/usr/bin/env bash\nwhile [ "$1" != -- ]; do shift; done; shift; exec "$@"\n' > "$G/bwrap"
  printf '#!/usr/bin/env bash\nwhile [ "$1" != -p ]; do shift; done; shift 2; exec "$@"\n' > "$G/sandbox-exec"
  chmod +x "$G/bwrap" "$G/sandbox-exec" && git -C "$S" branch trunk feature || fail "the stubs or the default branch"
}
t_setuplanes() {
  local X out f r; sample; X=$D/conveyor/conveyor.sh; lanestubs
  out=$(cd "$S" && bash "$X" setup --owner Dana --product src/ --test t --survey no --fast-lane yes --research-lane yes 2>&1) || fail "setup with yes to both lanes failed: $out"
  [ "$(git -C "$S-fast-lane" symbolic-ref --short HEAD)" = fast-lane ] && [ "$(git -C "$S-fast-lane" rev-parse HEAD)" = "$(git -C "$S" rev-parse trunk)" ] \
    || fail "setup did not make the fast lane on fast-lane at trunk: $(git -C "$S" worktree list)"
  [ "$(git -C "$S-research" rev-parse HEAD)" = "$(git -C "$S" rev-parse trunk)" ] && jq -e '.model == "claude-fable-5-2"' "$S-research/.claude/settings.local.json" >/dev/null \
    || fail "setup did not make the research lane with its settings: $(git -C "$S" worktree list)"
  jq -e --arg f "$S-fast-lane" --arg r "$S-research" '.records[0].lanes == {fast: {worktree: $f}, research: {worktree: $r}}' "$XDG_CONFIG_HOME/conveyor/host.json" >/dev/null \
    || fail "the host file does not name both lanes: $(cat "$XDG_CONFIG_HOME/conveyor/host.json")"
  [ "$(grep -c '^conveyor: created: the fast lane ' <<<"$out")" = 1 ] && [ "$(grep -c "^conveyor: created: the research lane's worktree " <<<"$out")" = 1 ] \
    || fail "setup did not print one created: line for each lane: $out"
  # Run again with yes: both lanes are there, and stay as they were.
  f=$(git -C "$S" worktree list --porcelain; cat "$S-research/.claude/settings.local.json"; find "$S-fast-lane" "$S-research" -printf '%p %m\n' | sort)
  out=$(cd "$S" && bash "$X" setup --fast-lane yes --research-lane yes 2>&1) || fail "setup run again with yes to both lanes failed: $out"
  r=$(git -C "$S" worktree list --porcelain; cat "$S-research/.claude/settings.local.json"; find "$S-fast-lane" "$S-research" -printf '%p %m\n' | sort)
  [ "$r" = "$f" ] && ! grep -q 'created:' <<<"$out" || fail "setup run again changed a lane, or said it made one: $out $(diff <(echo "$f") <(echo "$r"))"
}
# Bug: a pack an earlier setup wrote has no lanes.research, so yes to the research lane failed in its create; setup
# writes the default model and effort in, and makes the lane.
t_setuplaneoldpack() {
  local X out; sample; X=$D/conveyor/conveyor.sh; lanestubs
  (cd "$S" && bash "$X" setup --owner Dana --product src/ --test t --survey no --fast-lane no --research-lane no >/dev/null) || fail "setup from nothing exited non-zero"
  jq 'del(.lanes)' "$S/.conveyor/project.json" > "$G/pack" && mv "$G/pack" "$S/.conveyor/project.json" || fail "the old pack"
  out=$(cd "$S" && bash "$X" setup --fast-lane no --research-lane yes 2>&1) || fail "setup with yes to the research lane failed on a pack with no lanes.research: $out"
  jq -e '.lanes.research == {model: "claude-fable-5-2", effort: "medium"}' "$S/.conveyor/project.json" >/dev/null && [ -d "$S-research" ] \
    && jq -e '.model == "claude-fable-5-2"' "$S-research/.claude/settings.local.json" >/dev/null || fail "setup did not write lanes.research and make the lane: $out"
}
# Bug (#630): a new user had to write the host file and a terms file by hand before setup, and doctor named a missing
# terms file though it is optional. On a machine with no host file and no Conveyor but the plugin copy setup runs
# from ($D, as the plugin's own folder), setup with its answers writes the host file with the project as a record and
# the pack, and doctor then prints no fault, with no terms file anywhere: only ok: lines, each seat's route and check
# progress, and the one warning that the new pack sets no test.fileCommand.
t_setupfresh() {
  local X out; sample; X=$D/conveyor/conveyor.sh; rm "$XDG_CONFIG_HOME/conveyor/host.json" "$T/$CASE/terms"
  # A service whose conveyor.sh is there is no missing piece (as in t_doctor).
  mkdir -p "$XDG_CONFIG_HOME/systemd/user" && printf '[Service]\nExecStart="/bin/bash" "%s" machine\n' "$V/$B/conveyor/conveyor.sh" > "$XDG_CONFIG_HOME/systemd/user/conveyor-machine.service"
  # The open issues of t_setupheld (heldsample), for the line doctor prints of those setup held, at the end.
  echo '[{"number":3,"state":"open"},{"number":5,"state":"open"},{"number":6,"state":"closed"}]' > "$G/issues"
  out=$(cd "$S" && bash "$X" setup --fast-lane no --research-lane no --owner Dana --product src/ --test t --survey no --claude-key none --codex-key none 2>&1) \
    || fail "setup on a machine with no host file exited non-zero: $out"
  jq -e --arg m "$S" '.records == [{repo: "sample", main: $m}] and (has("terms") | not)' "$XDG_CONFIG_HOME/conveyor/host.json" >/dev/null && [ -s "$S/.conveyor/project.json" ] \
    || fail "setup did not write the host file with the project as its record, and the pack: $(cat "$XDG_CONFIG_HOME/conveyor/host.json" 2>&1)"
  # The Board started after setup (as setup asks the owner to), so doctor has no warning that it is not running.
  boardup; out=$(cd "$S" && PATH=$T/$CASE/board:$PATH CONVEYOR_DASHBOARD_PORT=8791 bash "$X" doctor 2>&1) || fail "doctor failed after setup with no terms file: $out"
  # Besides ok: lines, doctor prints only each seat's route (builder:, reviewer:) and the progress line of each seat's
  # check call (and of the judge's, askcheck()), which are information, not a check; and the one warning a fresh pack
  # is meant to get: setup sets no test.fileCommand, so a card with tests stops at its test step. Any other line is a fault.
  ! grep -vE '^(ok|builder|reviewer): |^conveyor: (checking .* with one call|asking the [a-z]+ \(.*\) one question with no tools) \(up to [0-9]+ s\)\.\.\.$' <<<"$out" \
    | grep -qvxF 'warning: a card runs each of its test files alone, and the pack sets no test.fileCommand, and Conveyor cannot run a.test.sh itself: it has no runner for a file of this kind; set test.fileCommand in .conveyor/project.json to a command that runs one test file' \
    && grep -qx 'ok: no terms file (it is optional): the privacy check runs with no word list' <<<"$out" \
    || fail "doctor after setup printed a line that is not ok:, a seat's route or check progress, or the test.list warning, or did not say the terms file is optional: $out"
  # Bug (#111, t_setupheld): doctor says what the control record setup wrote holds.
  grep -qxF 'ok: 2 open issues held; release one with `conveyor.sh control release <issue>` or on the Board' <<<"$out" || fail "doctor did not say what is held: $out"
}

# Bug (#111): setup wrote no control record, so the loop read the defaults (new issues start in the Queue) and queued
# and built every open issue of the project the moment its service started. Setup now writes the record with new
# issues held and every issue open then held. The sample's issues: 3 and 5 open, 6 closed (the newest).
heldsample() { # $X, $st (the sample's state folder) and $out (setup's output)
  sample; X=$D/conveyor/conveyor.sh
  echo '[{"number":3,"state":"open"},{"number":5,"state":"open"},{"number":6,"state":"closed"}]' > "$G/issues"
  out=$(cd "$S" && bash "$X" setup --fast-lane no --research-lane no --owner Dana --product src/ --test t --survey no 2>&1) || fail "setup exited non-zero: $out"
  st=$(cd "$S" && CONVEYOR_MAIN=$S bash "$X" state-dir) || fail "the state folder"
}
t_setupheld() {
  local X out st; heldsample
  jq -e '.start == "held" and .startHeld == [{from: 6, to: null}] and .held == [3, 5]' "$st/control.json" >/dev/null \
    || fail "setup did not write the record with new issues held and 3 and 5 held: $(cat "$st/control.json" 2>&1)"
  grep -qF 'new issues start held; 2 open issues held; release one with `conveyor.sh control release <issue>` or on the Board' <<<"$out" || fail "setup did not say what it held: $out"
  # What doctor says is held: t_setupfresh; doctor with no record: t_doctormissing, each in its one doctor run.
  # The first pass: the open issues as the loop reads them, with 7 opened after setup. With setup's record the pick
  # takes none; with no record (the defaults, as before) it takes one, so the answer is the record's doing.
  jq -cs . <(issue 3 2026-01-01 P1) <(issue 5 2026-02-01 P0) <(issue 7 2026-03-01 P0) > "$T/$CASE/open.json"
  [ "$(CONVEYOR_MAIN=$S bash "$X" pick --dry --issues "$T/$CASE/open.json" --state "$st")" = '' ] || fail "the loop's first pass after setup picks an issue"
  mkdir -p "$T/$CASE/none" && [ -n "$(CONVEYOR_MAIN=$S bash "$X" pick --dry --issues "$T/$CASE/open.json" --state "$T/$CASE/none")" ] \
    || fail "with no control record the pick takes nothing either, so the case above proves nothing"
}
# A second setup keeps the owner's later choices: new issues to the Queue, and 3 released.
t_setupheldkept() {
  local X out st was; heldsample
  (cd "$S" && CONVEYOR_MAIN=$S bash "$X" control start queue >/dev/null && CONVEYOR_MAIN=$S bash "$X" control release 3 >/dev/null) || fail "the owner's control actions failed"
  was=$(cat "$st/control.json"); jq -e '.start == "queue" and .held == [5]' <<<"$was" >/dev/null || fail "the owner's choices were not made: $was"
  out=$(cd "$S" && bash "$X" setup --fast-lane no --research-lane no 2>&1) || fail "setup run again exited non-zero: $out"
  [ "$(cat "$st/control.json")" = "$was" ] || fail "setup run again changed the control record: $was, now $(cat "$st/control.json")"
}
# #1155. Bug: setup had no way to write the project's own lint command, so the owner had to edit the pack by hand.
# --lint with its --lint-files writes it (the probe says ok); --lint alone asks for the files before anything is
# changed, and --lint-files alone is a wrong call. The probe's other results: t_setuplintprobe.
t_setuplint() {
  local X out was; setupdone
  was=$(setupstate); out=$(cd "$S" && bash "$X" setup --fast-lane no --research-lane no --lint true 2>&1); [ $? = 2 ] && [ "$(setupstate)" = "$was" ] \
    && grep -qF -- '--lint-files <a git pathspec of the files the lint command reads> (one for each)' <<<"$out" \
    || fail "setup --lint true with no --lint-files did not ask for the files before changing anything: $out"
  out=$(cd "$S" && bash "$X" setup --fast-lane no --research-lane no --lint-files '*.sh' 2>&1); [ $? = 2 ] && grep -q '^usage: .*--lint <command> --lint-files <pathspec>' <<<"$out" \
    || fail "setup --lint-files '*.sh' with no --lint was not refused as a wrong call: $out"
  out=$(cd "$S" && bash "$X" setup --fast-lane no --research-lane no --lint true --lint-files '*.sh' 2>&1) \
    && jq -e '.lint.commands == [{files: ["*.sh"], run: "true"}]' "$S/.conveyor/project.json" >/dev/null \
    && grep -qxF "conveyor: wrote the lint command true in the pack's lint.commands (the probe says ok)" <<<"$out" \
    || fail "setup --lint true --lint-files '*.sh' did not write the command: $(jq -c .lint "$S/.conveyor/project.json") $out"
  # Bug (#1156): setup said what checks a language with no ready entry only while the pack had no lint field, so a
  # pack whose size entry reads the Go files was never told that only their length is measured.
  jq '.lint.commands += [{files: ["*.go"], size: {file: 400, exempt: "x"}}]' "$S/.conveyor/project.json" > "$T/$CASE/p" \
    && mv "$T/$CASE/p" "$S/.conveyor/project.json" && : > "$S/a.go" && git -C "$S" add a.go || fail "the Go file and size entry"
  out=$(cd "$S" && bash "$X" setup --fast-lane no --research-lane no 2>&1) \
    && grep -qxF "conveyor: Conveyor has no ready lint entry for Go: for those files, only file length is measured, unless you give setup your own lint command as --lint" <<<"$out" \
    || fail "setup on a pack whose lint field has a size entry on *.go did not say that only file length is measured for Go: $out"
}
# #1155. Bug: setup would write a lint command that cannot run (its tool missing, an end the lint check cannot read,
# no file to read), which then fails or skips every card's lint check. setuplint probes each as doctor does: ok and
# findings are written, missing, error and empty are not, each saying why (error: a wrapper is needed); a command the
# pack runs already is not written twice. setuplint is called alone; pinreads, the project's install reading the new
# pack, is stubbed, as this main has no install (t_setuplint runs the real one).
t_setuplintprobe() {
  local r
  setup '[]'
  ( export CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards
    . "$SRC/conveyor.sh" state-dir > /dev/null && . "$SRC/lib/slots.sh" && . "$SRC/lib/prompts.sh" && . "$SRC/lib/push.sh" && . "$SRC/lib/lint.sh" && . "$SRC/lib/setup.sh" || exit 9
    pinreads() { :; }
    for r in 'exit 0' 'echo a.txt:1: E1 x; exit 1' 'echo lint: missing ruff; exit 127' 'echo the config is bad; echo more; exit 2'; do setuplint c "$r" '*.txt' || exit 8; done
    setuplint c true '*.py' && setuplint c 'exit 0' '*.txt' ) > "$T/$CASE/out" 2>&1; r=$?
  [ "$r" != 9 ] || fail "the engine could not be loaded: $(cat "$T/$CASE/out")"
  [ "$r" = 0 ] && [ "$(cat "$T/$CASE/out")" = "$(printf '%s\n' "conveyor: wrote the lint command exit 0 in the pack's lint.commands (the probe says ok)" \
    "conveyor: wrote the lint command echo a.txt:1: E1 x; exit 1 in the pack's lint.commands (the probe says findings: 1)" \
    'conveyor: the lint command echo lint: missing ruff; exit 127 was not written: the probe says missing: ruff; install it, then run setup again' \
    'conveyor: the lint command echo the config is bad; echo more; exit 2 was not written: the probe says error: the config is bad; it needs a wrapper script that ends 0 with no finding, 1 with finding lines (<path>:<line>: <text>) or 127 with the first line `lint: missing <tool>`: give that script to setup as --lint' \
    'conveyor: the lint command true was not written: the probe says empty: no tracked file matches --lint-files *.py' \
    "conveyor: the pack's lint.commands already has the lint command exit 0")" ] \
    || fail "setuplint's lines (exit $r) are not ok and findings written, missing, error and empty refused with why, a repeat kept once: $(cat "$T/$CASE/out")"
  jq -e '.lint.commands == [{files: ["*.txt"], run: "exit 0"}, {files: ["*.txt"], run: "echo a.txt:1: E1 x; exit 1"}]' "$R/.conveyor/project.json" >/dev/null \
    || fail "setuplint did not write ok and findings alone, once each: $(jq -c .lint "$R/.conveyor/project.json")"
}
# The engine's setup functions, loaded for a case that calls them alone; pinreads, the project's install reading the
# new pack, is stubbed, as the main of setup '[]' has no install (t_setupreadyask runs the real one).
setupfuncs() {
  export CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards
  . "$SRC/conveyor.sh" state-dir > /dev/null && . "$SRC/lib/slots.sh" && . "$SRC/lib/prompts.sh" && . "$SRC/lib/push.sh" && . "$SRC/lib/lint.sh" && . "$SRC/lib/setup.sh" || exit 9
  pinreads() { :; }
}
# #1156. Bugs: setup had no ready entry for a linter the project has set up, so the owner wrote the command by hand;
# a ready entry that edits files (--fix), lets warnings through, turns on rules of its own or fails while its tool is
# not installed; a linter's config left out of lint.policy, so a card could change it with no yes; a pyproject.toml,
# which holds more than lint config, put in lint.policy with no yes; a linter's config or pipelineFiles changed. In a
# project with the config of all three tools and a Go file: each is offered with its config, ruff with the
# pyproject.toml that holds its config as shared; written with --lint-shared no, then (on the same pack) yes.
t_setupready() {
  local r o
  setup '[]'
  printf 'line-length = 100\n' > "$R/ruff.toml"; printf '[project]\nname = "x"\n\n[tool.ruff.lint]\nselect = ["E"]\n' > "$R/pyproject.toml"
  printf 'disable=SC1091\n' > "$R/.shellcheckrc"; printf 'export default [];\n' > "$R/eslint.config.mjs"; printf 'package main\n' > "$R/main.go"
  git -C "$R" add ruff.toml pyproject.toml .shellcheckrc eslint.config.mjs main.go || fail "the configs could not be staged"
  ( cd "$R" && cat ruff.toml pyproject.toml .shellcheckrc eslint.config.mjs ) > "$T/$CASE/configs"
  cp "$R/.conveyor/project.json" "$T/$CASE/pack0"
  ( setupfuncs; o=$(lintready "$R") || exit 8; echo "$o" > "$T/$CASE/offer"
    setupready c "$o" no > "$T/$CASE/out.no" || exit 8; cp "$R/.conveyor/project.json" "$T/$CASE/pack.no"
    cp "$T/$CASE/pack0" "$R/.conveyor/project.json"; setupready c "$o" yes > "$T/$CASE/out.yes" || exit 8
    lintother "$R" > "$T/$CASE/other" || exit 8
    jq '.lint.commands += [{files: ["*.go"], size: {file: 400, exempt: "x"}}]' "$PACK" > "$T/$CASE/pack.size"
    PACK=$T/$CASE/pack.size; lintother "$R" > "$T/$CASE/other.size" || exit 8
    jq '.lint.commands += [{files: ["*.go"], run: "exit 0"}]' "$PACK" > "$T/$CASE/pack.run"
    PACK=$T/$CASE/pack.run; lintother "$R" > "$T/$CASE/other.run" || exit 8 ) 2>&1; r=$?
  [ "$r" = 0 ] || fail "lintready, setupready or lintother failed (exit $r)"
  jq -e 'map({tool, policy, shared, triggers: .entry.triggers}) == [
      {tool: "shellcheck", policy: [".shellcheckrc"], shared: [], triggers: [".shellcheckrc"]},
      {tool: "ruff", policy: ["ruff.toml"], shared: ["pyproject.toml"], triggers: ["ruff.toml", "pyproject.toml"]},
      {tool: "ESLint", policy: ["eslint.config.mjs"], shared: [], triggers: ["eslint.config.mjs"]}]' "$T/$CASE/offer" >/dev/null \
    || fail "lintready did not offer each tool with its own config, and ruff with pyproject.toml as shared: $(cat "$T/$CASE/offer")"
  jq -e '[.lint.commands[] | {files, run, complexity}] == [
      {files: ["*.sh"], run: "command -v shellcheck >/dev/null || { echo '\''lint: missing shellcheck'\''; exit 127; }; shellcheck -S warning -f gcc {files}", complexity: null},
      {files: ["*.py"], run: "command -v ruff >/dev/null || { echo '\''lint: missing ruff'\''; exit 127; }; ruff check --no-fix --force-exclude --output-format=concise {files}", complexity: ["C901", "PLR0915"]},
      {files: ["*.js", "*.mjs", "*.cjs"], run: .lint.commands[2].run, complexity: ["complexity", "max-lines-per-function", "max-depth"]}]
    and (.lint.commands[2].run | startswith("[ -x node_modules/.bin/eslint ] || { echo '\''lint: missing eslint'\''; exit 127; }; node_modules/.bin/eslint --max-warnings 0 --no-warn-ignored --format json {files} | "))
    and .lint.policy == [".shellcheckrc", "ruff.toml", "eslint.config.mjs"] and .pipelineFiles == null' "$T/$CASE/pack.no" >/dev/null \
    || fail "setupready with --lint-shared no did not write the three read-only entries and their own configs alone as lint.policy: $(jq -c .lint "$T/$CASE/pack.no")"
  ! jq -r '.lint.commands[].run' "$T/$CASE/pack.no" | grep -qE -- '--fix|--select|--extend-select|--rule|--ignore|(^| )-[ie] ' \
    || fail "a ready entry fixes files or sets a rule: $(jq -r '.lint.commands[].run' "$T/$CASE/pack.no")"
  jq -e '.lint.policy == [".shellcheckrc", "ruff.toml", "pyproject.toml", "eslint.config.mjs"] and .pipelineFiles == null' "$R/.conveyor/project.json" >/dev/null \
    || fail "setupready with --lint-shared yes did not put pyproject.toml in lint.policy: $(jq -c .lint.policy "$R/.conveyor/project.json")"
  ( cd "$R" && cat ruff.toml pyproject.toml .shellcheckrc eslint.config.mjs ) | cmp -s - "$T/$CASE/configs" || fail "setupready changed a linter's config file"
  grep -qxF "conveyor: the rules that measure complexity, which the ready entries do not turn on: ruff C901, PLR0915; ESLint complexity, max-lines-per-function, max-depth; turn them on in the linter's own config" "$T/$CASE/out.no" \
    && [ "$(grep -c complexity "$T/$CASE/out.no")" = 1 ] || fail "setupready did not name the complexity rules in one line: $(cat "$T/$CASE/out.no")"
  # Bug: setup said that file length is measured for Go when no size entry reads Go files (pack after the yes);
  # said nothing when a size entry does; named Go when a lint command with a run reads it.
  [ "$(cat "$T/$CASE/other")" = "conveyor: Conveyor has no ready lint entry for Go, and no lint command in the pack checks those files, not even their length: give setup your own lint command as --lint, or add a size entry to the pack's lint.commands" ] \
    || fail "lintother with no size entry on *.go did not say that nothing checks Go files: $(cat "$T/$CASE/other")"
  [ "$(cat "$T/$CASE/other.size")" = "conveyor: Conveyor has no ready lint entry for Go: for those files, only file length is measured, unless you give setup your own lint command as --lint" ] \
    || fail "lintother with a size entry on *.go did not say that only file length is measured for Go: $(cat "$T/$CASE/other.size")"
  [ ! -s "$T/$CASE/other.run" ] || fail "lintother named Go while a lint command with a run reads *.go: $(cat "$T/$CASE/other.run")"
  # Bug: the ESLint entry's filter lost findings or their place. Its run, with a stub eslint giving two messages of
  # one file, one with no rule and a newline in its text, must give each as one <path>:<line>:<col>: <rule> <text>.
  mkdir -p "$T/$CASE/es/node_modules/.bin"
  cat > "$T/$CASE/es/node_modules/.bin/eslint" <<'STUB'
#!/bin/sh
cat <<EOF
[{"filePath":"$(pwd -P)/a.js","messages":[{"line":3,"column":5,"ruleId":"no-unused-vars","message":"x is unused."},{"ruleId":null,"message":"Parsing error:\\nbad"}]}]
EOF
exit 1
STUB
  chmod +x "$T/$CASE/es/node_modules/.bin/eslint"
  o=$(jq -r '.lint.commands[2].run | sub("\\{files\\}"; "a.js")' "$T/$CASE/pack.no")
  o=$(cd "$T/$CASE/es" && bash -c "$o" 2>&1)
  [ "$o" = $'a.js:3:5: no-unused-vars x is unused.\na.js:1:1: eslint Parsing error: bad' ] \
    || fail "the ESLint entry on a stub eslint's two findings of a.js did not give one line for each: $o"
}
# #1156. Bug: setup offered a ready entry for a tool whose config the project does not have, or for a pyproject.toml
# with no ruff config in it. The fixture tracks a .sh file and a pyproject.toml with no [tool.ruff], and no linter
# config: nothing is offered.
t_setupreadynone() {
  local o
  setup '[]'
  printf '[project]\nname = "x"\n# [tool.ruff] is set in ruff.toml\n' > "$R/pyproject.toml"; git -C "$R" add pyproject.toml || fail "pyproject.toml could not be staged"
  [ -n "$(git -C "$R" ls-files -- '*.sh')" ] || fail "the fixture tracks no .sh file"
  o=$( setupfuncs; lintready "$R" ) || fail "lintready failed: $o"
  [ "$o" = '[]' ] || fail "lintready offered an entry in a project with no linter config: $o"
}
# #1156. Bugs: setup did not ask for the ready entries or for the shared pyproject.toml, wrote one with no yes, or
# dropped the --lint-shared answer; with its own --lint on other files, it said nothing of the Go files no command
# reads. A whole setup run, as only it shows the questions asked before anything is changed and the answers read: a
# project with ruff.toml, a pyproject.toml with [tool.ruff] and a Go file is asked --lint-ready and --lint-shared and
# nothing changes; with yes to both and --lint on *.toml, the entry and both files in lint.policy are written, and Go
# is named.
t_setupreadyask() {
  local X out was; setupdone
  printf 'line-length = 100\n' > "$S/ruff.toml"; printf '[tool.ruff]\nline-length = 100\n' > "$S/pyproject.toml"; printf 'package main\n' > "$S/main.go"
  git -C "$S" add ruff.toml pyproject.toml main.go || fail "the fixture files could not be staged"
  was=$(setupstate); out=$(cd "$S" && bash "$X" setup --fast-lane no --research-lane no 2>&1); [ $? = 2 ] && [ "$(setupstate)" = "$was" ] \
    && grep -qF -- '--lint-ready <yes or no: write the ready lint entries, ruff (for ruff.toml, pyproject.toml), in the pack' <<<"$out" \
    && grep -qF -- "--lint-shared <yes or no: pyproject.toml holds ruff's config" <<<"$out" \
    || fail "setup in a project with ruff.toml and pyproject.toml did not ask --lint-ready and --lint-shared before changing anything: $out"
  out=$(cd "$S" && bash "$X" setup --fast-lane no --research-lane no --lint-ready yes --lint-shared yes --lint 'exit 0' --lint-files '*.toml' 2>&1) \
    && jq -e '[.lint.commands[] | .files] == [["*.py"], ["*.toml"]] and .lint.policy == ["ruff.toml", "pyproject.toml"]' "$S/.conveyor/project.json" >/dev/null \
    && grep -qxF "conveyor: wrote the ready lint entry for ruff in the pack's lint.commands, on *.py" <<<"$out" \
    && grep -qF "conveyor: Conveyor has no ready lint entry for Go, and no lint command in the pack checks those files" <<<"$out" \
    && [ "$(cat "$S/ruff.toml")" = 'line-length = 100' ] \
    || fail "setup --lint-ready yes --lint-shared yes --lint 'exit 0' --lint-files '*.toml' did not write the ruff entry and both configs as lint.policy, and name Go: $(jq -c .lint "$S/.conveyor/project.json") $out"
}
