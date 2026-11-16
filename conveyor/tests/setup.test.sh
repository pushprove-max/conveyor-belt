#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: setup and doctor.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# A sample project with no Conveyor in it, $S, on a feature branch, whose origin's default branch is trunk (with no
# refs/remotes/origin/HEAD to say so), beside the code repo ($D, the plugin copy at commit $B), and a gh,
# claude and codex stubbed in $G: gh's labels are $G/labels, those it created $G/created; it is signed out while
# $G/out is there. Like GitHub, it lists every label (no first page only) and refuses to create one the repo has
# under any case. The case's own host file names a readable terms file. All but the host file is made once per run
# (samplemake, lib.sh template) and copied.
sample() {
  coderepo; trap 'chmod -R u+w "$T/$CASE"' EXIT
  # CLAUDE_CONFIG_DIR: Claude Code's folder, where its record of installed plugins is, the case's own (empty).
  export S=$T/$CASE/sample G=$T/$CASE/gh XDG_CONFIG_HOME=$T/$CASE/config CLAUDE_CONFIG_DIR=$T/$CASE/claude
  template sample samplemake && mkdir -p "$XDG_CONFIG_HOME/conveyor" "$XDG_DATA_HOME/conveyor" && cp -a "$FIXTURE.sample/sample" "$S" \
    && cp -a "$FIXTURE.sample/origin.git" "$T/$CASE/origin.git" && git -C "$S" remote set-url origin "$T/$CASE/origin.git" \
    && cp -a "$FIXTURE.sample/gh" "$G" && cp -a "$FIXTURE.sample/board-venv" "$XDG_DATA_HOME/conveyor/board-venv" \
    || fail "the sample repo was not made"
  # The plugin's one release, v1.0.0, is the plugin copy's commit $B (gh lists $G/releases).
  git -C "$D" tag v1.0.0 "$B" && git -C "$D" push -q origin v1.0.0 && echo '[{"tagName":"v1.0.0","isDraft":false,"isPrerelease":false}]' > "$G/releases" \
    || fail "the plugin's release was not made"
  PATH=$G:$PATH
  echo 'case:Zed' > "$T/$CASE/terms"; jq -n --arg t "$T/$CASE/terms" '{terms: $t}' > "$XDG_CONFIG_HOME/conveyor/host.json"
}
samplemake() { # <folder>: what sample copies, in <folder>: sample, origin.git, gh (G) and board-venv
  local S=$1/sample G=$1/gh
  mkdir -p "$S" "$G" "$1/board-venv/bin" && git -C "$S" init -q -b feature \
    && git init -q --bare -b trunk "$1/origin.git" && git -C "$S" remote add origin "$1/origin.git" \
    && git -C "$S" -c user.name=t -c user.email=t${AT}example.com commit -q --allow-empty -m one && git -C "$S" push -q origin feature:trunk \
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
  "issue create") # each issue filed, its arguments as a JSON list a line in $G/filed, numbered from 101
    printf '%s\0' "${@:3}" | jq -cRs 'split("\u0000")[:-1]' >> "$G/filed" && echo "https://github.com/example/sample/issues/$((100 + $(wc -l < "$G/filed")))" ;;
  *) exit 1 ;;
esac
EOF
  # claude: `plugin install <plugin>` records it in $G/claude-installs and, as Claude Code does, in its record of
  # installed plugins in CLAUDE_CONFIG_DIR; anything else does nothing.
  cat > "$G/claude" <<'EOF'
#!/usr/bin/env bash
[ "$1 $2" = "plugin install" ] || exit 0
mkdir -p "$CLAUDE_CONFIG_DIR/plugins" && echo "$3" >> "$G/claude-installs" \
  && jq -n --arg p "$3" '{version: 2, plugins: {($p): [{scope: "user"}]}}' > "$CLAUDE_CONFIG_DIR/plugins/installed_plugins.json"
EOF
  printf '#!/bin/sh\n' > "$G/codex"; chmod +x "$G/gh" "$G/claude" "$G/codex" || return 1
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
  rm -r "$S/conveyor"
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
    && grep -qF 'conveyor/README.md, The CPU budget of a test file' <<<"$out" || fail "setup did not say how to wrap each test file's run: $out"
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
# the groups of slow files and the shared helpers; the answer is not saved, so every setup run asks again and a yes
# files again; --survey cannot ask for another later.
t_setupsurvey() {
  local X out; sample; X=$D/conveyor/conveyor.sh
  out=$(cd "$S" && bash "$X" setup --fast-lane no --research-lane no --owner Dana --product src/ --test t --survey yes 2>&1) || fail "setup --survey yes exited non-zero: $out"
  [ "$(jq -c '[.[1], .[3], .[5]]' "$G/filed")" = '["Test-speed survey, first","bug","P1"]' ] && grep -q '^conveyor: filed #101, Test-speed survey, first$' <<<"$out" \
    && jq -e '.test.firstSurvey == true' "$S/.conveyor/project.json" >/dev/null \
    || fail "setup --survey yes did not file exactly one first survey issue of the monthly kind, or did not save the answer: $(cat "$G/filed" 2>&1) $out"
  jq -e '.[7] | contains("each of the project'"'"'s test files alone") and contains("clock seconds") and contains("CPU seconds")
      and contains("over the CPU budget of 8 CPU s") and contains("each group of files over the budget")
      and contains("each shared helper the measurements point to") and contains("for the Foreman to file as cards")' "$G/filed" >/dev/null \
    || fail "the first survey's issue does not ask for each file alone, the groups over budget and the shared helpers: $(jq -r '.[7]' "$G/filed")"
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
# the pack, and doctor then prints only ok: lines, with no terms file anywhere.
t_setupfresh() {
  local X out; sample; X=$D/conveyor/conveyor.sh; rm "$XDG_CONFIG_HOME/conveyor/host.json" "$T/$CASE/terms"
  # A service whose conveyor.sh is there is no missing piece (as in t_doctor).
  mkdir -p "$XDG_CONFIG_HOME/systemd/user" && printf '[Service]\nExecStart="/bin/bash" "%s" machine\n' "$V/$B/conveyor/conveyor.sh" > "$XDG_CONFIG_HOME/systemd/user/conveyor-machine.service"
  out=$(cd "$S" && bash "$X" setup --fast-lane no --research-lane no --owner Dana --product src/ --test t --survey no 2>&1) || fail "setup on a machine with no host file exited non-zero: $out"
  jq -e --arg m "$S" '.records == [{repo: "sample", main: $m}] and (has("terms") | not)' "$XDG_CONFIG_HOME/conveyor/host.json" >/dev/null && [ -s "$S/.conveyor/project.json" ] \
    || fail "setup did not write the host file with the project as its record, and the pack: $(cat "$XDG_CONFIG_HOME/conveyor/host.json" 2>&1)"
  out=$(cd "$S" && bash "$X" doctor 2>&1) || fail "doctor failed after setup with no terms file: $out"
  # Besides ok: lines, doctor prints only each seat's route (builder:, reviewer:), which is information, not a check.
  ! grep -qvE '^(ok|builder|reviewer): ' <<<"$out" && grep -qx 'ok: no terms file (it is optional): the privacy check runs with no word list' <<<"$out" \
    || fail "doctor after setup printed a line that is not ok:, or did not say the terms file is optional: $out"
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
# The pinned commit's install removed, as the fix of a damaged one leaves it.
uninstalled() { chmod -R u+w "$V/$B" && rm -rf "$V/$B"; }

# Bugs: doctor passes with a piece missing, or names one without its fix; a missing jq or git stops it before it
# names the rest.
t_doctor() {
  local X out; doctordone
  # The last card test run recorded test times (times), the one before it none: no word of missing times.
  doctortests '{}' '{times: {"a.test": 1}}'
  # A service whose conveyor.sh is there (the machine's, on the pinned install) is no missing piece.
  mkdir -p "$XDG_CONFIG_HOME/systemd/user" && printf '[Service]\nExecStart="/bin/bash" "%s" machine\n' "$V/$B/conveyor/conveyor.sh" > "$XDG_CONFIG_HOME/systemd/user/conveyor-machine.service"
  out=$(cd "$S" && bash "$X" doctor 2>&1) || fail "doctor failed with everything in place: $out"
  ! grep -q '^missing' <<<"$out" && grep -q '^ok: the pinned commit' <<<"$out" && grep -q '^ok: codex' <<<"$out" && grep -q '^ok: the terms file' <<<"$out" \
    && grep -q "^ok: segno, in the Board's virtualenv " <<<"$out" && ! grep -q 'no test times' <<<"$out" \
    && grep -qx 'ok: the plugin mattpocock-skills@claude-plugins-official, for /conveyor-belt:plan' <<<"$out" || fail "doctor with everything in place: $out"
}
# The project's card test lines, one for each jq object given, added to its test line (lib/views.sh UNTIMED), in the
# state folder of the sample (doctor's, as it runs in that checkout; state-dir alone names the plugin copy's).
doctortests() { # <jq object>...
  local s o; s=$(cd "$S" && CONVEYOR_MAIN=$S bash "$X" state-dir) && mkdir -p "$s" || fail "the state folder"
  for o in "$@"; do jq -cn "{card: \"c0-1\", issue: 1, step: \"test\", time: \"2026-11-01T00:00:00Z\", result: \"pass\"} + $o"; done >> "$s/cards.jsonl"
}
# Bug caught (#515): a project's test command printed no `TESTRUN sec` lines, so none of its cards recorded test times
# and no file was held to the CPU budget, and doctor said nothing. Its last card test runs, a pass and a fail, recorded
# none (a later line of a batch that reused a run, and one that selected no file, are no run): doctor warns, naming
# the README section that says how to add them, and still passes.
t_doctoruntimed() {
  local X out; doctordone
  doctortests '{}' '{result: "fail"}' '{reused: true, times: null}' '{ended: "nothing selected"}'
  out=$(cd "$S" && bash "$X" doctor 2>&1) || fail "doctor failed over test times: $out"
  grep -qxF 'warning: the last 2 card test runs recorded no test times: the test command prints no `TESTRUN sec` lines; conveyor/README.md, The CPU budget of a test file, says how to add them' <<<"$out" \
    || fail "doctor did not warn that the last card test runs recorded no test times: $out"
}
t_doctormissing() {
  local X out; doctordone
  rm "$T/$CASE/terms" "$CLAUDE_CONFIG_DIR/plugins/installed_plugins.json"; : > "$G/out"; uninstalled; echo segno > "$G/nopkg"
  local gone=d791d168d791d168d791d168d791d168d791d168; mkdir -p "$XDG_CONFIG_HOME/systemd/user" \
    && printf '[Service]\nExecStart="/bin/bash" "%s" serve\n' "$V/$gone/conveyor/conveyor.sh" > "$XDG_CONFIG_HOME/systemd/user/conveyor-gone-1.service"
  # The host file's one record is another checkout of the same folder name (setup adds no second record of a name).
  jq --arg m "$T/$CASE/other/sample" '.records = [{repo: "sample", main: $m}]' "$XDG_CONFIG_HOME/conveyor/host.json" > "$T/$CASE/h" \
    && mv "$T/$CASE/h" "$XDG_CONFIG_HOME/conveyor/host.json" || fail "the host file was not rewritten"
  out=$(cd "$S" && PATH=$(without codex) bash "$X" doctor 2>&1) && fail "doctor passed with pieces missing: $out"
  # Bug caught (#17): the machine's Conveyor did not serve this checkout, as no record of the host file named it, and
  # doctor printed only "ok: the host file".
  grep -q "^missing: a record of the host file $XDG_CONFIG_HOME/conveyor/host.json for this checkout $S .*; fix: run /conveyor-belt:setup; .*add {\"repo\": \"<name>\", \"main\": \"$S\"}" <<<"$out" \
    || fail "doctor did not name the missing record of this checkout in the host file: $out"
  grep -qx "missing: segno, for the Board, in its virtualenv $XDG_DATA_HOME/conveyor/board-venv; fix: run /conveyor-belt:setup, which installs it there" <<<"$out" \
    && grep -q "^ok: pyotp, in the Board's virtualenv " <<<"$out" || fail "doctor did not name the Board's missing package with its fix: $out"
  rm "$G/nopkg"
  # Bug caught (#573): a service named an install that prune had removed, so a restart or a reboot would not start
  # its loop, and doctor said nothing.
  grep -qxF "missing: the file $V/$gone/conveyor/conveyor.sh that the service $XDG_CONFIG_HOME/systemd/user/conveyor-gone-1.service starts (a restart or a reboot does not start its loop); fix: run conveyor.sh install-service in the project's checkout, which writes the machine's service on an installed commit" <<<"$out" \
    || fail "doctor did not name a service whose conveyor.sh is gone, with that file: $out"
  grep -q '^missing: codex, .*; fix: install it (npm install -g @openai/codex)' <<<"$out" && grep -qx 'missing: gh signed in; fix: run gh auth login' <<<"$out" \
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
# neither can be read or searched (mode 000), which a fix that only grants write could not empty.
t_doctordamaged() {
  local X out l; doctordone; uninstalled
  mkdir -p "$V/$B/sub"; : > "$V/$B/sub/f"; chmod 000 "$V/$B/sub" "$V/$B"; out=$(cd "$S" && bash "$X" doctor 2>&1)
  ! (cd "$S" && bash "$X" install "$B" >/dev/null 2>&1) || fail "install took a damaged version folder"
  l=$(grep "^missing: the install of the pinned commit $B (.*); fix: remove it (" <<<"$out") || fail "doctor gave no fix that removes a damaged install: $out"
  l=${l#*fix: remove it (}; eval "${l%%), then run /conveyor-belt:setup*}" && [ ! -e "$V/$B" ] || fail "doctor's removal did not remove the damaged install: $out"
  (cd "$S" && bash "$X" install "$B" >/dev/null 2>&1) && uninstalled || fail "the install failed after doctor's fix"
}
# The command is the owner's to paste: it holds when the data folder has an apostrophe, and removes a dangling link,
# which chmod cannot follow, as well as a damaged folder.
doctorquoted() { # <link | folder>
  local X out l q="$T/$CASE/owner's-data" k=$1; doctordone
  mkdir -p "$q/conveyor/versions"; [ $k = link ] && ln -s "$T/$CASE/nowhere" "$q/conveyor/versions/$B" || mkdir "$q/conveyor/versions/$B"
  out=$(cd "$S" && XDG_DATA_HOME=$q bash "$X" doctor 2>&1)
  l=$(grep "^missing: the install of the pinned commit $B (.*); fix: remove it (" <<<"$out") || fail "doctor gave no fix that removes a damaged install ($k): $out"
  l=${l#*fix: remove it (}; eval "${l%%), then run /conveyor-belt:setup*}" && [ ! -e "$q/conveyor/versions/$B" ] && [ ! -L "$q/conveyor/versions/$B" ] \
    || fail "doctor's removal did not remove the damaged install ($k) under a data folder with an apostrophe: $out"
}
t_doctorlink() { doctorquoted link; }
t_doctorfolder() { doctorquoted folder; }
# A pin that is not a full commit id can climb out of the versions folder: doctor never offers a folder it names for
# removal, here one that exists outside it.
t_doctorclimb() {
  local X out; doctordone
  mkdir -p "$T/$CASE/outside"; cp "$S/.conveyor/project.json" "$T/$CASE/pin"
  jq --arg c "../../../../../../../../../../../../../..$T/$CASE/outside" '.plugin.commit = $c' "$T/$CASE/pin" > "$S/.conveyor/project.json"
  out=$(cd "$S" && bash "$X" doctor 2>&1); mv "$T/$CASE/pin" "$S/.conveyor/project.json"
  [ -d "$T/$CASE/outside" ] && ! grep -q 'rm -\|remove it' <<<"$out" || fail "doctor offered to remove a folder outside the versions folder: $out"
}
# A snapshot folder that says gh is signed in is no word on this machine's gh (signed out here).
# Bug caught (#17): on Debian or Ubuntu with no python3-venv, setup cannot make the Board's virtualenv, and doctor's
# fix, "run setup", failed the same way: with no virtualenv, the fix names python3-venv.
t_doctornovenv() {
  local X out; doctordone; rm -r "$XDG_DATA_HOME/conveyor/board-venv"
  out=$(cd "$S" && bash "$X" doctor 2>&1) && fail "doctor passed with no Board virtualenv: $out"
  grep -qxF "missing: the Board's virtualenv $XDG_DATA_HOME/conveyor/board-venv; fix: run /conveyor-belt:setup, which makes it (on Debian or Ubuntu, first install python3-venv: sudo apt install python3-venv)" <<<"$out" \
    && ! grep -q 'for the Board, in its virtualenv' <<<"$out" || fail "doctor's fix for a missing Board virtualenv does not name python3-venv: $out"
}
# Bug caught (#20): with no python3-venv, python3 -m venv makes bin/python3 and then fails in ensurepip; doctor took
# that virtualenv for made and said only to run setup again, and setup's rerun did not make it again.
t_doctorvenvnopip() {
  local X out py; doctordone; py=$(type -P python3) || fail "no python3 on PATH"
  echo pip > "$G/nopkg" # the virtualenv's python3 has no pip
  # python3 as on Debian with no python3-venv: venv records its arguments and fails.
  printf '#!/usr/bin/env bash\n[ "$1 $2" != "-m venv" ] || { echo "$*" >> "%s/venv"; exit 1; }\nexec "%s" "$@"\n' "$G" "$py" > "$G/python3" && chmod +x "$G/python3"
  ! (cd "$S" && bash "$X" setup --fast-lane no --research-lane no --owner Dana --product src/ --test t --survey no --pin >/dev/null 2>&1) || fail "setup passed with a virtualenv with no pip"
  grep -qxF -- "-m venv --clear $XDG_DATA_HOME/conveyor/board-venv" "$G/venv" || fail "setup did not make again a virtualenv with no pip: $(cat "$G/venv" 2>&1)"
  out=$(cd "$S" && bash "$X" doctor 2>&1) && fail "doctor passed with a virtualenv with no pip: $out"
  grep -qxF "missing: the Board's virtualenv $XDG_DATA_HOME/conveyor/board-venv; fix: run /conveyor-belt:setup, which makes it (on Debian or Ubuntu, first install python3-venv: sudo apt install python3-venv)" <<<"$out" \
    && ! grep -q 'for the Board, in its virtualenv' <<<"$out" || fail "doctor's fix for a virtualenv with no pip does not name python3-venv: $out"
}
t_doctorsnap() {
  local X out; doctordone; : > "$G/out"
  mkdir -p "$T/$CASE/snap"; echo true > "$T/$CASE/snap/gh"
  out=$(cd "$S" && CONVEYOR_GITHUB=$T/$CASE/snap bash "$X" doctor 2>&1)
  grep -qx 'missing: gh signed in; fix: run gh auth login' <<<"$out" || fail "doctor took a snapshot's word that gh is signed in: $out"
}
# A private repo needs no terms file; with no host file, that is named; with no pack, setup is the fix.
t_doctorprivate() {
  local X out; doctordone
  jq '.privacy.mode = "private"' "$S/.conveyor/project.json" > "$T/$CASE/p" && mv "$T/$CASE/p" "$S/.conveyor/project.json"
  rm "$XDG_CONFIG_HOME/conveyor/host.json"; out=$(cd "$S" && bash "$X" doctor 2>&1)
  ! grep -q 'terms file' <<<"$out" && grep -q "^missing: the host file $XDG_CONFIG_HOME/conveyor/host.json; fix: run /conveyor-belt:setup" <<<"$out" || fail "doctor, private and no host file: $out"
}
t_doctorhostbad() {
  local X out; doctordone; uninstalled
  jq '.privacy.mode = "private"' "$S/.conveyor/project.json" > "$T/$CASE/p" && mv "$T/$CASE/p" "$S/.conveyor/project.json"
  echo '[' > "$XDG_CONFIG_HOME/conveyor/host.json"; out=$(cd "$S" && bash "$X" doctor 2>&1)
  grep -q '^missing: a readable host file .*; fix: make it a JSON object' <<<"$out" && grep -q '^missing: the install' <<<"$out" || fail "doctor stopped at, or passed, a host file that does not read: $out"
}
t_doctornopack() {
  local X out; doctordone
  rm -r "$S/.conveyor"; out=$(cd "$S" && bash "$X" doctor 2>&1)
  grep -q "^missing: the pack $S/.conveyor/project.json; fix: run /conveyor-belt:setup" <<<"$out" || fail "doctor with no pack: $out"
}
# jq, git and gh not on PATH: each is named, and the project's checks are named as not checked; so is a valid host file.
t_doctortools() {
  local X out; doctordone; rm -r "$S/.conveyor"
  echo '{}' > "$XDG_CONFIG_HOME/conveyor/host.json"; out=$(cd "$S" && CONVEYOR_MAIN=$S PATH=$(without jq git gh) bash "$X" doctor 2>&1) && fail "doctor passed with no jq, git or gh: $out"
  grep -q '^missing: jq; fix: install jq' <<<"$out" && grep -q '^missing: git; fix: install git' <<<"$out" && grep -q '^missing: gh, the GitHub CLI; fix: install it' <<<"$out" \
    && grep -q '^not checked: the pack' <<<"$out" && grep -q '^not checked: the host file' <<<"$out" && ! grep -q 'host file.*fix' <<<"$out" \
    || fail "doctor with no jq, git or gh: $out"
}
