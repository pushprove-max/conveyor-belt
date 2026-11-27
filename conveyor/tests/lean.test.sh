#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases: the lean settings (lib/lean.sh): setup --lean-settings yes writing Claude Code's three settings and
# Serena's web dashboard off, each with a backup, and doctor's line; a key the user set kept; --lean-settings no
# taking away only what still holds Conveyor's value; a settings file that is not JSON left as it is. An engine
# update writing again only the keys never written is install.test.sh's t_leaninstall.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# The case's own Claude folder, Serena folder and data folder (where the record is), never this machine's.
leanhome() {
  export CLAUDE_CONFIG_DIR=$T/$CASE/cc SERENA_HOME=$T/$CASE/serena XDG_DATA_HOME=$T/$CASE/data
  mkdir -p "$CLAUDE_CONFIG_DIR" "$XDG_DATA_HOME" || fail "the case's folders were not made"
}
# <command> [args] of lib/lean.sh, run as setup and doctor run it; its output in $T/$CASE/lean.out, its exit in RC.
leanrun() { ( . "$SRC/lib/portable.sh" && . "$SRC/lib/lean.sh" && "$@" ) > "$T/$CASE/lean.out" 2>&1; RC=$?; }
LEANSET='{"env":{"CLAUDE_CODE_ENABLE_AWAY_SUMMARY":"0","CLAUDE_CODE_ENABLE_PROMPT_SUGGESTION":"false","FOO":"1"},"skillListingMaxDescChars":400,"theme":"dark"}'
# Bug (#1825): setup never touched the user's Claude settings, so each machine kept prompt suggestions (the whole
# context sent again for each), away summaries and the long skill descriptions. setup --lean-settings yes writes the
# three keys into the file the settings link leads to, the link kept, with a backup of the file as it was; it turns
# Serena's web dashboard off (that line only, its comment kept) with a backup; doctor then names each one as set. A
# whole setup and doctor run (the sample): only they show that setup reads --lean-settings and doctor prints its line.
t_leansetup() {
  local X out f b; sample; X=$D/conveyor/conveyor.sh; leanhome; mkdir -p "$T/$CASE/dots" "$SERENA_HOME"
  echo '{"theme": "dark", "env": {"FOO": "1"}}' > "$T/$CASE/dots/settings.json" && ln -s "$T/$CASE/dots/settings.json" "$CLAUDE_CONFIG_DIR/settings.json"
  printf '%s\n' 'gui_log_window: false' 'web_dashboard: true # the dashboard' 'log_level: 20' > "$SERENA_HOME/serena_config.yml"
  out=$(cd "$S" && bash "$X" setup --fast-lane no --research-lane no --owner Dana --product src/ --test t --survey no --pin --lean-settings yes 2>&1) \
    || fail "setup --lean-settings yes exited non-zero: $out"
  f=$T/$CASE/dots/settings.json
  [ -L "$CLAUDE_CONFIG_DIR/settings.json" ] && [ "$(jq -cS . "$f")" = "$LEANSET" ] \
    || fail "setup --lean-settings yes did not write the three keys into the file the link leads to, keeping the user's: $(jq -c . "$f" 2>&1); link kept: $([ -L "$CLAUDE_CONFIG_DIR/settings.json" ] && echo yes); $out"
  b=$(compgen -G "$f.conveyor-*.bak") && [ "$(jq -c . "$b")" = '{"theme":"dark","env":{"FOO":"1"}}' ] \
    || fail "setup --lean-settings yes left no backup of the settings as they were beside $f: $(ls "$T/$CASE/dots")"
  [ "$(cat "$SERENA_HOME/serena_config.yml")" = $'gui_log_window: false\nweb_dashboard: false # the dashboard\nlog_level: 20' ] \
    && b=$(compgen -G "$SERENA_HOME/serena_config.yml.conveyor-*.bak") && grep -qx 'web_dashboard: true # the dashboard' "$b" \
    || fail "setup --lean-settings yes did not turn Serena's dashboard line alone off, with a backup: $(cat "$SERENA_HOME/serena_config.yml"); $(ls "$SERENA_HOME")"
  [ "$(jq -c '[.answer, .added]' "$XDG_DATA_HOME/conveyor/lean-settings.json")" = '["yes",["env.CLAUDE_CODE_ENABLE_AWAY_SUMMARY","env.CLAUDE_CODE_ENABLE_PROMPT_SUGGESTION","serena:web_dashboard","skillListingMaxDescChars"]]' ] \
    || fail "setup --lean-settings yes did not record the answer and each key it wrote: $(cat "$XDG_DATA_HOME/conveyor/lean-settings.json" 2>&1)"
  out=$(cd "$S" && bash "$X" doctor 2>&1)
  grep -qxF 'note: lean settings (setup --lean-settings): answer yes; env.CLAUDE_CODE_ENABLE_PROMPT_SUGGESTION set, env.CLAUDE_CODE_ENABLE_AWAY_SUMMARY set, skillListingMaxDescChars set; Serena config: web_dashboard set' <<<"$out" \
    || fail "doctor, after setup --lean-settings yes, did not name each lean setting as set: $(grep -i lean <<<"$out")"
}
# Bug (#1825): a key the user set is the user's: yes writes only the absent ones and leaves the user's values, and
# doctor names them set by the user. With no Serena config, nothing is made and doctor says so.
t_leanuser() {
  leanhome
  echo '{"skillListingMaxDescChars": 1000, "env": {"CLAUDE_CODE_ENABLE_AWAY_SUMMARY": "1"}}' > "$CLAUDE_CONFIG_DIR/settings.json"
  leanrun leanset yes
  [ "$RC" = 0 ] && [ "$(jq -cS . "$CLAUDE_CONFIG_DIR/settings.json")" = '{"env":{"CLAUDE_CODE_ENABLE_AWAY_SUMMARY":"1","CLAUDE_CODE_ENABLE_PROMPT_SUGGESTION":"false"},"skillListingMaxDescChars":1000}' ] \
    || fail "leanset yes changed a key the user set, or did not write the absent one (exit $RC): $(cat "$CLAUDE_CONFIG_DIR/settings.json"); $(cat "$T/$CASE/lean.out")"
  [ ! -e "$SERENA_HOME" ] && [ "$(jq -c .added "$XDG_DATA_HOME/conveyor/lean-settings.json")" = '["env.CLAUDE_CODE_ENABLE_PROMPT_SUGGESTION"]' ] \
    || fail "leanset yes recorded a key it did not write, or made a Serena folder: $(cat "$XDG_DATA_HOME/conveyor/lean-settings.json")"
  leanrun leandoctor
  [ "$(cat "$T/$CASE/lean.out")" = 'note: lean settings (setup --lean-settings): answer yes; env.CLAUDE_CODE_ENABLE_PROMPT_SUGGESTION set, env.CLAUDE_CODE_ENABLE_AWAY_SUMMARY set by the user, skillListingMaxDescChars set by the user; Serena config: none' ] \
    || fail "leandoctor did not name the user's keys as set by the user and Serena's config as none: $(cat "$T/$CASE/lean.out")"
}
# Bug (#1825): no after yes must take away what Conveyor wrote and nothing the user changed since: a key the user set
# to another value stays, and Serena's dashboard line goes back to true only while it is still false. The undo is run
# as the setup page names it, `conveyor.sh setup --lean-settings no` alone (it stopped asking for the lanes' answers
# before any change), and under another CLAUDE_CONFIG_DIR and SERENA_HOME whose files hold the user's own copies of
# Conveyor's values: it read the folders named then, and took the user's values from files it never wrote.
t_leanno() {
  local o=$T/$CASE/other out
  leanhome; mkdir -p "$SERENA_HOME" "$o/cc" "$o/serena" && git init -q "$T/$CASE/p" || fail "the case's folders were not made"
  echo '{"theme": "dark"}' > "$CLAUDE_CONFIG_DIR/settings.json"; echo 'web_dashboard: true' > "$SERENA_HOME/serena_config.yml"
  leanrun leanset yes; [ "$RC" = 0 ] || fail "leanset yes exited $RC: $(cat "$T/$CASE/lean.out")"
  jq '.skillListingMaxDescChars = 300' "$CLAUDE_CONFIG_DIR/settings.json" > "$T/$CASE/s" && mv "$T/$CASE/s" "$CLAUDE_CONFIG_DIR/settings.json"
  echo '{"skillListingMaxDescChars": 400}' > "$o/cc/settings.json"; echo 'web_dashboard: false' > "$o/serena/serena_config.yml"
  out=$(cd "$T/$CASE/p" && CLAUDE_CONFIG_DIR=$o/cc SERENA_HOME=$o/serena bash "$SRC/conveyor.sh" setup --lean-settings no 2>&1) \
    || fail "conveyor.sh setup --lean-settings no, given alone, exited non-zero: $out"
  [ "$(jq -c . "$o/cc/settings.json")" = '{"skillListingMaxDescChars":400}' ] && [ "$(cat "$o/serena/serena_config.yml")" = 'web_dashboard: false' ] \
    || fail "setup --lean-settings no under another CLAUDE_CONFIG_DIR and SERENA_HOME changed the user's files there: $(cat "$o/cc/settings.json" "$o/serena/serena_config.yml"); $out"
  [ "$(jq -cS . "$CLAUDE_CONFIG_DIR/settings.json")" = '{"env":{},"skillListingMaxDescChars":300,"theme":"dark"}' ] \
    || fail "setup --lean-settings no did not take away the two keys holding Conveyor's value from the file it wrote, or took the one the user changed: $(cat "$CLAUDE_CONFIG_DIR/settings.json"); $out"
  [ "$(cat "$SERENA_HOME/serena_config.yml")" = 'web_dashboard: true' ] && [ "$(jq -c '[.answer, .added]' "$XDG_DATA_HOME/conveyor/lean-settings.json")" = '["no",[]]' ] \
    || fail "leanset no did not turn Serena's dashboard back on and save the answer no: $(cat "$SERENA_HOME/serena_config.yml"); $(cat "$XDG_DATA_HOME/conveyor/lean-settings.json")"
}
# Bug (#1825): a settings file that is not JSON cannot be merged into: it is left as it is, with no backup, the line
# names it, and no key of it is recorded as written (an update tries again once the file is fixed). The file holds
# two objects, one after the other: a check that reads only its last value takes it for an object and writes both.
t_leanbad() {
  leanhome
  printf '{"theme": "dark"}\n{}\n' > "$CLAUDE_CONFIG_DIR/settings.json"; cp "$CLAUDE_CONFIG_DIR/settings.json" "$T/$CASE/was"
  leanrun leanset yes
  cmp -s "$CLAUDE_CONFIG_DIR/settings.json" "$T/$CASE/was" && ! compgen -G "$CLAUDE_CONFIG_DIR/settings.json.conveyor-*" >/dev/null \
    || fail "leanset yes changed, or backed up, a settings file that is not JSON: $(cat "$CLAUDE_CONFIG_DIR/settings.json"); $(ls "$CLAUDE_CONFIG_DIR")"
  grep -qxF "Claude settings not changed: $CLAUDE_CONFIG_DIR/settings.json is not valid JSON" "$T/$CASE/lean.out" \
    && [ "$(jq -c '[.answer, .added]' "$XDG_DATA_HOME/conveyor/lean-settings.json")" = '["yes",[]]' ] \
    || fail "leanset yes on a settings file that is not JSON did not say so, or recorded a key (exit $RC): $(cat "$T/$CASE/lean.out"); $(cat "$XDG_DATA_HOME/conveyor/lean-settings.json")"
}
