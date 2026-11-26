#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# test-changed.sh on this checkout's own engine area map, on a scratch copy of every file it names (the parts of
# test-changed.test.sh that need that copy, apart from it because each part below copies it: a change to the map runs
# both files, side by side). The shared setup is in test-changed.lib.sh.
set -u
HERE=$(cd "$(dirname "$0")" && pwd -P); ROOT=$(dirname "$HERE")
. "$HERE/test-changed.lib.sh"

# This checkout's own map, on a scratch copy of every file it names, each case file holding one case named after it
# (t_<file>): a change to one engine file runs the case files its area names, not the whole engine test; a change to
# what every case runs through (the dispatcher, the shared setup) still runs the whole. Each part below has its own
# copy of it (M). A run here loops over every case file of the map, so each of these parts makes one run (two only
# where both are cheap whole runs), and the parts that start from the same commit build it with one <name>fix function.
M=$T/m; mkdir -p "$M/.conveyor" "$M/conveyor/tests"
cp "$HERE/test-changed.sh" "$HERE/test-share.sh" "$HERE/lint-shell.sh" "$HERE/engine-areas.json" "$M/.conveyor/"; : > "$M/.conveyor/test-lint.sh"; : > "$M/.conveyor/no-browser-tests.sh"; : > "$M/.conveyor/no-records-split.sh"
jq -r '.areas[].files[] | split("/")[:-1] | join("/")' "$HMAP" | sort -u | (cd "$M" && xargs mkdir -p)
jq -r '.areas[].files[]' "$HMAP" | while read -r f; do echo one > "$M/$f"; done
for c in "$ROOT"/conveyor/tests/*.test.sh; do s=${c##*/}; s=${s%.test.sh}; printf 't_%s() {\n  :\n}\n' "$s" > "$M/conveyor/tests/$s.test.sh"; done
echo 'echo "${CONVEYOR_SHELL_TEST_CASE:-ALL}" >> "${0%/*}/../ran"' > "$M/conveyor/conveyor.test.sh"
cp "$R/.conveyor/project.json" "$M/.conveyor/"
echo ran > "$M/.gitignore"
git -C "$M" init -q && git -C "$M" add -A && git -C "$M" commit -qm init
mran() { rm -f "$M/ran"; (cd "$M" && bash .conveyor/test-changed.sh) > "$T/out" 2>&1; echo $? > "$T/rc"; ranlines "$M/ran"; }
# shellcheck disable=SC2154 # cases is set in test-changed.lib.sh
marea() { # <engine file>; leaves the case files the run ran in mgot
  local f=$1 want got
  want=$(jq -r --arg f "$f" '.areas[] | select(.files | index($f)) | .tests[]' "$HMAP" | sed 's/[.]test[.]sh$//' | sort | tr '\n' ' ')
  echo two >> "$M/$f"; got=$(mran); echo one > "$M/$f"; mgot=$got
  [ -n "$want" ] && [ "$got" = "${want% }" ] && [ "$(wc -w <<<"$got")" -lt "$cases" ] && [ "$(cat "$T/rc")" = 0 ] \
    && ok "a change to $f alone runs its area's case files ($got), not the whole engine test" \
    || no "$f changed: ran '$got', want '$want' of $cases case files, exit $(cat "$T/rc"): $(cat "$T/out")"
}
p_mtestrun() { marea conveyor/lib/testrun.sh; }
p_mreview() { marea conveyor/lib/review.sh; }
p_mclaim() { marea conveyor/lib/claim.sh; }
# Bug (#398, issue 543): a change to conveyor/lib/snapshot.sh broke the since case of rules.test.sh, which reads the
# snapshot's fields, and the change's run never ran it. Each case file here builds a snapshot and reads its fields
# (setup.test.sh and doctorbudget.test.sh through doctor's Board check, dashboard.sh --check), so a change to
# snapshot.sh alone must run it. Issue 1439: lintyes.test.sh checks the waiting sentence snapshot.sh builds for a card
# that also changes lint policy, and a change to snapshot.sh did not run it.
p_msnapshot() {
  local c missing
  mgot=''; marea conveyor/lib/snapshot.sh
  missing=$(for c in rules accounts accountsflight boardone budget clis codex fail giveway landas machine machinehold \
    mainred modellist models opencode proxyroute records rerun samefile slices slots snapkept stall standing testmapbuild \
    testrules transcript watch setup doctorbudget lintyes; do
    [[ " $mgot " == *" $c "* ]] || echo "$c"
  done)
  [ -z "$missing" ] && ok "a change to conveyor/lib/snapshot.sh runs each case file that reads the snapshot's fields" \
    || no "conveyor/lib/snapshot.sh changed: ran '$mgot', without the snapshot readers: $missing"
}
p_mall() {
  echo two >> "$M/conveyor/tests/lib.sh"; got=$(mran)
  [ "$got" = ALL ] && ok "a change to conveyor/tests/lib.sh runs the whole engine test" || no "conveyor/tests/lib.sh changed: ran '$got': $(cat "$T/out")"
}
# Issue 513. Bug: any change to the dispatcher, conveyor.sh (core, an "all" area), ran the whole engine test, 74 case
# files, though it only reworded a message. D1: a reworded echo message runs the case file that holds it (wait's), not
# the whole engine test. D2: a changed code line still runs the whole.
mdispfix() {
  printf '#!/usr/bin/env bash\nset -u\necho "the dispatcher could not start its loop"\n' > "$M/conveyor/conveyor.sh"
  printf 't_wait() {\n  grep -q "could not start its loop" out\n}\n' > "$M/conveyor/tests/wait.test.sh"
  git -C "$M" commit -qam dispatcher
}
p_mdisp() {
  mdispfix
  sed 's/could not/cannot/' "$M/conveyor/conveyor.sh" > "$T/e" && cat "$T/e" > "$M/conveyor/conveyor.sh"; got=$(mran)
  [ "$got" = wait ] && [ "$(cat "$T/rc")" = 0 ] && ok "a reworded echo message in conveyor/conveyor.sh runs the case file that holds it, not the whole engine test" \
    || no "conveyor.sh echo reworded: ran '$got', exit $(cat "$T/rc"): $(cat "$T/out")"
}
p_mdispcode() {
  mdispfix
  git -C "$M" show HEAD:conveyor/conveyor.sh | sed 's/^set -u$/set -e/' > "$T/e" && cat "$T/e" > "$M/conveyor/conveyor.sh"; got=$(mran)
  [ "$got" = ALL ] && ok "a changed code line in conveyor/conveyor.sh runs the whole engine test" || no "conveyor.sh code changed: ran '$got': $(cat "$T/out")"
}
# Issue 513. Bug: the base area's test pack fixtures (test-pack.json, test-hooks.json, test-card-rules.md) were no
# file a text-only change could be, so a blank line or a reworded card rule there ran the whole engine test. Blanks in
# the JSON run no engine case; a reworded rule runs the case file that holds it; a changed JSON value still runs all.
mbasefix() {
  printf '{\n  "owner": {"name": "Sample"}\n}\n' > "$M/conveyor/lib/test-pack.json"
  printf '{"hooks": {}}\n' > "$M/conveyor/lib/test-hooks.json"
  printf '# Test pack card rules\n\n- PACK-CARD-RULE: the test pack rule given to every card.\n' > "$M/conveyor/lib/test-card-rules.md"
  printf 't_wait() {\n  grep -q "rule given to every card" out\n}\n' > "$M/conveyor/tests/wait.test.sh"
  git -C "$M" commit -qam fixtures
}
p_mbase() {
  mbasefix
  printf '\n' >> "$M/conveyor/lib/test-pack.json"; printf '{ "hooks": { } }\n' > "$M/conveyor/lib/test-hooks.json"; got=$(mran)
  [ -z "$got" ] && [ "$(cat "$T/rc")" = 0 ] && ok "blanks added to the test pack's JSON fixtures run no engine case, not the whole engine test" \
    || no "test pack JSON blanks: ran '$got', exit $(cat "$T/rc"): $(cat "$T/out")"
}
p_mbaserule() {
  mbasefix
  sed 's/given to/given to each and/' "$M/conveyor/lib/test-card-rules.md" > "$T/e" && cat "$T/e" > "$M/conveyor/lib/test-card-rules.md"; got=$(mran)
  [ "$got" = wait ] && [ "$(cat "$T/rc")" = 0 ] && ok "a reworded rule in test-card-rules.md runs the case file that holds it, not the whole engine test" \
    || no "test-card-rules.md reworded: ran '$got', exit $(cat "$T/rc"): $(cat "$T/out")"
}
p_mbasevalue() {
  mbasefix
  sed 's/Sample/Other/' "$M/conveyor/lib/test-pack.json" > "$T/e" && cat "$T/e" > "$M/conveyor/lib/test-pack.json"; got=$(mran)
  [ "$got" = ALL ] && ok "a changed value in test-pack.json runs the whole engine test" || no "test-pack.json value changed: ran '$got': $(cat "$T/out")"
}
# Issue 514. Bug: any code change to paths.sh (base, an "all" area) ran the whole engine test, 74 case files, though
# it changed one function that only some areas call. D1: a changed function body runs the case file that calls it
# (wait) and the case file that calls rv, its caller in review.sh (stall; issue 1775: callersof, one hop, so not the
# areas of review.sh and of claim.sh, whose cl calls cardaccts, another caller), not pick.sh's whose comment names it.
# D2: a changed top-level line, or a function a top-level line calls at start-up, still runs the whole.
mfuncsfix() {
  printf 'HOST=x\nnohost() {\n  :\n}\nnohost\nguardread() { # <control record>\n  echo one\n}\ncardaccts() { guardread; } 2>/dev/null\n' \
    > "$M/conveyor/lib/paths.sh"
  printf 'rv() { guardread; }\n' > "$M/conveyor/lib/review.sh"; printf 'cl() { cardaccts; }\n' > "$M/conveyor/lib/claim.sh"
  printf '# guardread() reads the guard\n' > "$M/conveyor/lib/pick.sh"; printf 't_wait() {\n  guardread\n}\n' > "$M/conveyor/tests/wait.test.sh"
  printf 't_stall() {\n  rv\n}\n' > "$M/conveyor/tests/stall.test.sh"
  git -C "$M" commit -qam functions
}
p_mfuncs() {
  mfuncsfix
  sed 's/echo one/echo two/' "$M/conveyor/lib/paths.sh" > "$T/e" && cat "$T/e" > "$M/conveyor/lib/paths.sh"; got=$(mran)
  [ "$got" = "stall wait" ] && [ "$(cat "$T/rc")" = 0 ] \
    && ok "a changed function body in paths.sh runs the case files that call it or its callers ($got), not the whole engine test" \
    || no "paths.sh guardread() changed: ran '$got', want 'stall wait', exit $(cat "$T/rc"): $(cat "$T/out")"
}
p_mfuncsall() {
  mfuncsfix
  git -C "$M" show HEAD:conveyor/lib/paths.sh | sed 's/^HOST=x$/HOST=y/' > "$M/conveyor/lib/paths.sh"; got=$(mran)
  [ "$got" = ALL ] && ok "a changed top-level line of paths.sh runs the whole engine test" || no "paths.sh top-level line changed: ran '$got': $(cat "$T/out")"
  git -C "$M" show HEAD:conveyor/lib/paths.sh | sed 's/^  :$/  true/' > "$M/conveyor/lib/paths.sh"; got=$(mran)
  [ "$got" = ALL ] && ok "a changed function of paths.sh that runs at start-up runs the whole engine test" || no "paths.sh nohost() changed: ran '$got': $(cat "$T/out")"
}
# Issue 514. Bug: any code change to conveyor.sh ran the whole engine test, though it changed one command's line of
# its command table (issue 530: the table replaced the dispatch case). D3: a changed command line runs the case files
# that run that command (`loop retry`, and `loop <main> retry` through a case file's own loop, `bash "$X" retry` with
# X set to conveyor.sh's path), not machine's that runs shut; with its usage text reworded too, also the case file
# that holds the text. A command the shared setup runs (state-dir), or a change to setup() itself (D4), runs the
# whole. Issue 530 D1: a command line added to the table runs only the case file that runs that command (pick's).
mcmdsfix() {
  printf '#!/usr/bin/env bash\nset -u\n# The command table.\ncmd() { :; }\ncmd retry retry.sh %s\n# Shut a card.\ncmd shut shut.sh %s\ncmd state-dir state-dir.sh %s\necho "usage: conveyor.sh" >&2\n' \
    "'retry <issue>'" "'shut <issue>'" "'state-dir'" > "$M/conveyor/conveyor.sh"
  printf 'loop() { bash "$SRC/conveyor.sh" "$@"; }\nsetup() {\n  ST=$(loop state-dir)\n}\n' > "$M/conveyor/tests/lib.sh"
  printf 't_control() {\n  loop retry 5\n}\n' > "$M/conveyor/tests/control.test.sh"
  printf 'loop() { bash "$SRC/conveyor.sh" "${@:2}"; }\nt_batch() {\n  loop "$S" retry 5\n}\n' > "$M/conveyor/tests/batch.test.sh"
  printf 't_machine() {\n  loop shut 5\n}\n' > "$M/conveyor/tests/machine.test.sh"
  printf 'go() { X=$D/conveyor/conveyor.sh; }\nt_setup() {\n  go; bash "$X" retry 5\n}\n' > "$M/conveyor/tests/setup.test.sh"
  printf 't_wait() {\n  grep -q "the usage of retry <issue>" out\n}\n' > "$M/conveyor/tests/wait.test.sh"
  printf 't_pick() {\n  loop again 5\n}\n' > "$M/conveyor/tests/pick.test.sh"
  git -C "$M" commit -qam dispatch
}
mcmdsretry() { sed 's/^cmd retry retry.sh /cmd retry again.sh /' "$M/conveyor/conveyor.sh" > "$T/e" && cat "$T/e" > "$M/conveyor/conveyor.sh"; }
p_mcmds() {
  mcmdsfix; mcmdsretry; got=$(mran)
  [ "$got" = "batch control setup" ] && [ "$(cat "$T/rc")" = 0 ] \
    && ok "a changed command line in conveyor.sh runs the case files that run that command, not the whole engine test" \
    || no "conveyor.sh retry line changed: ran '$got', want 'batch control setup', exit $(cat "$T/rc"): $(cat "$T/out")"
}
p_mcmdsusage() {
  mcmdsfix; mcmdsretry
  sed "s/'retry <issue>'/'retry <issue> [--now]'/" "$M/conveyor/conveyor.sh" > "$T/e" && cat "$T/e" > "$M/conveyor/conveyor.sh"; got=$(mran)
  [ "$got" = "batch control setup wait" ] && [ "$(cat "$T/rc")" = 0 ] \
    && ok "a changed command line with a reworded usage text runs that command's case files and the one that holds the text" \
    || no "conveyor.sh retry line and usage changed: ran '$got', want 'batch control setup wait', exit $(cat "$T/rc"): $(cat "$T/out")"
}
p_mcmdsadd() {
  mcmdsfix
  git -C "$M" show HEAD:conveyor/conveyor.sh | awk '/^cmd shut / { print "cmd again again.sh \047again <issue>\047" } 1' > "$M/conveyor/conveyor.sh"; got=$(mran)
  [ "$got" = pick ] && [ "$(cat "$T/rc")" = 0 ] \
    && ok "a command line added to the table runs only the case file that runs that command, not the whole engine test" \
    || no "conveyor.sh again line added: ran '$got', want 'pick', exit $(cat "$T/rc"): $(cat "$T/out")"
}
p_mcmdsall() {
  mcmdsfix
  git -C "$M" show HEAD:conveyor/conveyor.sh | sed 's/state-dir.sh/dir.sh/' > "$M/conveyor/conveyor.sh"; got=$(mran)
  [ "$got" = ALL ] && ok "a changed command that the shared test setup runs runs the whole engine test" || no "conveyor.sh state-dir line changed: ran '$got': $(cat "$T/out")"
  git -C "$M" checkout -q -- conveyor/conveyor.sh
  sed 's/ST=/export ST=/' "$M/conveyor/tests/lib.sh" > "$T/e" && cat "$T/e" > "$M/conveyor/tests/lib.sh"; got=$(mran)
  [ "$got" = ALL ] && ok "a changed setup() in conveyor/tests/lib.sh runs the whole engine test" || no "tests/lib.sh setup() changed: ran '$got': $(cat "$T/out")"
}
# Issue 530. Bug: the control record's defaults were a line of paths.sh (base, an "all" area), so a key added to them
# ran the whole engine test. D2: a key added to control-defaults.json runs only the case file that reads the file
# (control's), not the whole engine test nor control.sh's area; a changed default runs also the case files of the code
# that reads that key (pick.sh reads .mode), not those of code that reads another (push.sh, .rules.push).
mdefaultsfix() {
  printf '{\n  "mode": "run",\n  "rules": {\n    "push": true\n  }\n}\n' > "$M/conveyor/lib/control-defaults.json"
  printf 'CTL0=$(jq -c . "$HERE/lib/control-defaults.json")\nctl() { jq -c --argjson d "$CTL0" %s "$CONTROL"; }\n' "'\$d * .'" > "$M/conveyor/lib/control.sh"
  printf 'paused() { jq -e %s <<<"$1"; }\n' "'.mode == \"pause\"'" > "$M/conveyor/lib/pick.sh"
  printf 'pushes() { jq -e %s <<<"$1"; }\n' "'.rules.push'" > "$M/conveyor/lib/push.sh"
  printf 't_control() {\n  jq -c . "$SRC/lib/control-defaults.json"\n}\n' > "$M/conveyor/tests/control.test.sh"
  git -C "$M" commit -qam defaults
}
p_mdefaults() {
  mdefaultsfix
  jq '.later = true' "$M/conveyor/lib/control-defaults.json" > "$T/e" && cat "$T/e" > "$M/conveyor/lib/control-defaults.json"; got=$(mran)
  [ "$got" = control ] && [ "$(cat "$T/rc")" = 0 ] \
    && ok "a key added to the control record's defaults runs the case file that reads them, not the whole engine test" \
    || no "control-defaults.json key added: ran '$got', want 'control', exit $(cat "$T/rc"): $(cat "$T/out")"
}
p_mdefaultsmode() {
  mdefaultsfix
  want=$({ jq -r '.areas[] | select(.files | index("conveyor/lib/pick.sh")) | .tests[]' "$HMAP"; echo control.test.sh; } \
    | sed 's/[.]test[.]sh$//' | sort -u | tr '\n' ' ')
  git -C "$M" show HEAD:conveyor/lib/control-defaults.json | jq '.mode = "pause"' > "$M/conveyor/lib/control-defaults.json"; got=$(mran)
  [ "$got" = "${want% }" ] && [ "$(wc -w <<<"$got")" -lt "$cases" ] && [ "$(cat "$T/rc")" = 0 ] \
    && ok "a changed default runs the case files of the code that reads that key ($got), not the whole engine test" \
    || no "control-defaults.json mode changed: ran '$got', want '${want% }', exit $(cat "$T/rc"): $(cat "$T/out")"
}
# A map change runs only the case files it renamed, but beside a change to the shared test setup it still runs the whole.
mmapwait() { jq '.areas.slots.tests += ["wait.test.sh"]' "$HMAP" | lines > "$M/.conveyor/engine-areas.json"; }
p_mmap() {
  mmapwait; got=$(mran)
  [ "$got" = wait ] && ok "a map change that adds wait.test.sh to an area runs that case file alone" || no "map, wait.test.sh added: ran '$got': $(cat "$T/out")"
}
p_mmaplib() {
  mmapwait; echo two >> "$M/conveyor/tests/lib.sh"; got=$(mran)
  [ "$got" = ALL ] && ok "a map change with a change to conveyor/tests/lib.sh runs the whole engine test" || no "map and tests/lib.sh changed: ran '$got': $(cat "$T/out")"
}

# Each of these runs loops over every case file of the map, so they are the slowest parts, and the file takes about as
# long as the last of them to end.
for p in mtestrun mreview mclaim msnapshot mall mdisp mdispcode mbase mbaserule mbasevalue mmap mmaplib mfuncs mfuncsall \
  mcmds mcmdsusage mcmdsadd mcmdsall mdefaults mdefaultsmode; do part "$p" m; done
results
