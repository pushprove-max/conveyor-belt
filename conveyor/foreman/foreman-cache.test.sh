#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 60
# The Foreman's 1-hour prompt cache outside the launcher: foreman.sh setup writes it into the main checkout's
# .claude/settings.local.json, and foreman.sh claim says when the claiming session runs with another cache time.
# Bug (#714): a Foreman claimed with /conveyor-belt:foreman in an ordinary session kept the user's 5-minute cache, so
# its turns 5 to 60 minutes apart wrote the whole cache again (about a quarter of its cost), and nothing said so.
set -uo pipefail
SRC=$(cd "$(dirname "$0")" && pwd -P)
B=$(mktemp -d) || exit 1
trap 'rm -rf "$B"' EXIT
cd "$B" || exit 1
unset CONVEYOR_FOREMAN CONVEYOR_FOREMAN_LAUNCH CONVEYOR_CARD CONVEYOR_LANE CLAUDE_CONFIG_DIR CLAUDE_PROJECT_DIR CLAUDE_CODE_PROMPT_CACHE_TTL
# A claim opens the Board in the browser (board-open.test.sh, with a stub opener); here no claim may open a real one.
export CLAUDE_PLUGIN_OPTION_boardAutoOpen=false
# Records cannot be asked here: the live summary says so, which the claim's context prints all the same.
export CONVEYOR_FOREMAN_ASK='exit 3'
# fixture <case>: a project alpha (its pack follows the plugin's main), the only record of a host of its own.
fixture() {
  T=$B/$1 CASE=$1
  export HOME=$T/home XDG_CONFIG_HOME=$T/config XDG_DATA_HOME=$T/data XDG_STATE_HOME=$T/xstate
  M=$T/alpha
  export CONVEYOR_FOREMAN_DIR=$T/foreman CONVEYOR_MAIN=$M
  mkdir -p "$HOME" "$XDG_CONFIG_HOME/conveyor" "$CONVEYOR_FOREMAN_DIR" && git init -q "$M" && mkdir -p "$M/.conveyor" "$M/.claude" \
    && jq -n '{plugin: {follow: "main"}}' > "$M/.conveyor/project.json" \
    && jq -n --arg m "$M" --arg s "$T/state" '{stateDir: $s, records: [{repo: "alpha", main: $m}]}' > "$XDG_CONFIG_HOME/conveyor/host.json" \
    || fail "the fixture was not made"
}
fail() { echo "FAIL [cache-$CASE]: $*" >&2; exit 1; }

# D1: setup sets env.CLAUDE_CODE_PROMPT_CACHE_TTL to 1h and keeps the file's other keys, the env's too; a file that
# is not a JSON object is left byte for byte, and setup says so.
t_setup() {
  fixture setup
  L=$M/.claude/settings.local.json
  # A checkout with no settings.local.json yet (a fresh one) gets one with the 1-hour cache alone.
  out=$(bash "$SRC/foreman.sh" setup 2>&1) || fail "setup failed with no settings.local.json: $out"
  jq -e '. == {env: {CLAUDE_CODE_PROMPT_CACHE_TTL: "1h"}}' "$L" > /dev/null 2>&1 \
    || fail "setup did not write a new settings.local.json with the 1-hour cache: $(cat "$L" 2>&1)"
  jq -n '{permissions: {allow: ["Bash(ls)"]}, env: {FOO: "bar", CLAUDE_CODE_PROMPT_CACHE_TTL: "5m"}, model: "x"}' > "$L"
  out=$(bash "$SRC/foreman.sh" setup 2>&1) || fail "setup failed: $out"
  jq -e '.env == {FOO: "bar", CLAUDE_CODE_PROMPT_CACHE_TTL: "1h"} and .permissions.allow == ["Bash(ls)"] and .model == "x"' "$L" > /dev/null \
    || fail "setup did not set the 1-hour cache and keep the other keys: $(cat "$L")"
  echo '[1, 2]' > "$L"
  out=$(bash "$SRC/foreman.sh" setup 2>&1) || fail "setup failed on a file that is not an object: $out"
  [ "$(cat "$L")" = '[1, 2]' ] || fail "setup rewrote a settings file that is not a JSON object: $(cat "$L")"
  grep -qF "$L is not a JSON object, so it is left as it is" <<<"$out" || fail "setup did not say it left the file: $out"
}
# D2: the claim says the cache time when the session's is set and not 1h; with 1h or none set it says nothing of it.
t_claim() {
  fixture claim
  line='The Foreman runs with the prompt cache time'
  out=$(CLAUDE_CODE_PROMPT_CACHE_TTL=5m bash "$SRC/foreman.sh" claim s5) || fail "the claim with 5m failed: $out"
  [ "$(grep -cF "$line 5m, not 1h: a restart of this session takes the 1-hour cache from $M/.claude/settings.local.json" <<<"$out")" = 1 ] \
    || fail "the claim with a 5-minute cache does not say so in one line: $out"
  out=$(CLAUDE_CODE_PROMPT_CACHE_TTL=1h bash "$SRC/foreman.sh" claim s1) || fail "the claim with 1h failed: $out"
  ! grep -qF "$line" <<<"$out" || fail "the claim with the 1-hour cache spoke of the cache time: $out"
  out=$(bash "$SRC/foreman.sh" claim s0) || fail "the claim with no cache time set failed: $out"
  ! grep -qF "$line" <<<"$out" || fail "the claim with no cache time set spoke of the cache time: $out"
  # The role asked for in words: the session is told to reply with the cache line too, as it is told to omit the rest
  # of the claim's output. Bug: the reply was the claim's first line alone, so the owner never saw the warning.
  say() { # <session> <ttl>: the words hook as Claude Code runs it in a session in the main checkout
    jq -cn --arg s "$1" --arg c "$M" '{session_id: $s, prompt: "start your role", cwd: $c}' \
      | (cd "$M" && CLAUDE_PROJECT_DIR=$M CLAUDE_CODE_PROMPT_CACHE_TTL=$2 CONVEYOR_HOOK=1 bash "$SRC/foreman.sh" words) \
      | jq -r '.hookSpecificOutput.additionalContext'
  }
  out=$(say w5 5m)
  grep -qF "Reply with only these two lines: This session is now the Foreman" <<<"$out" \
    && grep -qxF "$line 5m, not 1h: a restart of this session takes the 1-hour cache from $M/.claude/settings.local.json, which /conveyor-belt:setup --foreman writes." <<<"$(sed -n 2p <<<"$out")" \
    || fail "the words claim with a 5-minute cache does not ask for the cache line in the reply: $out"
  out=$(say w1 1h)
  grep -qF "Reply with only this one line: This session is now the Foreman" <<<"$out" \
    || fail "the words claim with the 1-hour cache asks for more than the first line: $out"
}

# D1 to D3 of #1751: foreman.compactAt in the host file is the one source of CLAUDE_AUTOCOMPACT_PCT_OVERRIDE in both
# settings files, and launch hands it to claude. Bug: no setting made the Foreman's session short, so each turn read
# about 180,000 tokens again.
t_compact() {
  fixture compact
  # setup clears CONVEYOR_FOREMAN_DIR: the launcher's settings are in the host record's state folder, not $T/foreman.
  L=$M/.claude/settings.local.json S=$T/state/foreman/settings.json H=$XDG_CONFIG_HOME/conveyor/host.json
  host() { jq --argjson v "$1" '.foreman = {compactAt: $v}' "$H" > "$H.new" && mv "$H.new" "$H"; }
  both() { # <expected value, a JSON string, or "none">: the variable in both files, a string, or not there at all
    local f ok
    for f in "$L" "$S"; do
      if [ "$1" = none ]; then jq -e '.env | has("CLAUDE_AUTOCOMPACT_PCT_OVERRIDE") | not' "$f" > /dev/null 2>&1; ok=$?
      else jq -e --arg v "$1" '.env.CLAUDE_AUTOCOMPACT_PCT_OVERRIDE == $v' "$f" > /dev/null 2>&1; ok=$?; fi
      [ "$ok" = 0 ] || fail "CLAUDE_AUTOCOMPACT_PCT_OVERRIDE should be $1 (a string, or not there for none) in $f: $(cat "$f")"
    done
  }
  jq -n '{env: {FOO: "bar"}, model: "x"}' > "$L"
  host 40
  out=$(bash "$SRC/foreman.sh" setup 2>&1) || fail "setup with foreman.compactAt 40 failed: $out"
  both 40
  jq -e '.env.FOO == "bar" and .model == "x" and .env.CLAUDE_CODE_PROMPT_CACHE_TTL == "1h"' "$L" > /dev/null \
    || fail "setup with foreman.compactAt 40 lost other settings: $(cat "$L")"
  # launch hands the value to claude, as it hands the cache time; a stand-in claude writes what it was given.
  # stub: a stand-in claude on PATH, as the real one would start a session; only the environment it is given is read.
  mkdir -p "$T/bin" && printf '#!/usr/bin/env bash\necho "pct=${CLAUDE_AUTOCOMPACT_PCT_OVERRIDE-unset}"\n' > "$T/bin/claude" && chmod +x "$T/bin/claude" \
    || fail "the stand-in claude was not made"
  launched() { (cd "$M" && env -u CONVEYOR_FOREMAN_DIR -u CLAUDE_AUTOCOMPACT_PCT_OVERRIDE PATH="$T/bin:$PATH" bash "$SRC/foreman.sh" launch 2>&1); }
  out=$(launched); [ "$out" = pct=40 ] || fail "launch with foreman.compactAt 40 gave claude '$out', not pct=40"
  # The key taken out: the next setup takes the variable out of both files and keeps the rest.
  jq 'del(.foreman)' "$H" > "$H.new" && mv "$H.new" "$H"
  out=$(bash "$SRC/foreman.sh" setup 2>&1) || fail "setup with no foreman.compactAt failed: $out"
  both none
  jq -e '.env.FOO == "bar" and .env.CLAUDE_CODE_PROMPT_CACHE_TTL == "1h"' "$L" > /dev/null || fail "taking the variable out lost other settings: $(cat "$L")"
  out=$(launched); [ "$out" = pct=unset ] || fail "launch with no foreman.compactAt gave claude '$out', not pct=unset"
  # A value that is no whole number from 1 to 100 fails, names the key and the value, and leaves both files as they were.
  host 40; bash "$SRC/foreman.sh" setup > /dev/null 2>&1 || fail "setup with foreman.compactAt 40 failed again"
  cp "$L" "$B/l.before"; cp "$S" "$B/s.before"
  for v in 0 101 40.5 '"high"' '"40"' true '[40]'; do
    host "$v"
    out=$(bash "$SRC/foreman.sh" setup 2>&1) && fail "setup passed with foreman.compactAt $v: $out"
    [ "$out" = "foreman: foreman.compactAt in $H is $(jq -c . <<<"$v"), not a whole number from 1 to 100" ] \
      || fail "setup with foreman.compactAt $v did not name the key and the value in one line: $out"
    cmp -s "$L" "$B/l.before" && cmp -s "$S" "$B/s.before" || fail "setup with foreman.compactAt $v changed a settings file"
  done
}
# D4 of #1751: a compact runs the SessionStart hooks again (no matcher), so `start` and `rules` print the rules and the
# saved state to the compacted Foreman session. Setup's compact point depends on that: the session loses its start text.
t_aftercompact() {
  fixture aftercompact
  F=$CONVEYOR_FOREMAN_DIR
  bash "$SRC/foreman.sh" setup > /dev/null 2>&1 || fail "setup failed"
  printf '# rules\n- RULE-MARKER-1751\n' > "$F/rules.md"
  printf '# alpha: saved state\n- STATE-MARKER-1751 open item\n' >> "$F/state.md"
  bash "$SRC/foreman.sh" claim sc > /dev/null 2>&1 || fail "the claim failed"
  inp=$(jq -cn --arg c "$M" '{session_id: "sc", source: "compact", cwd: $c}')
  out=$(cd "$M" && CLAUDE_PROJECT_DIR=$M CONVEYOR_HOOK=1 bash "$SRC/foreman.sh" start --rules-apart <<<"$inp" | jq -r '.hookSpecificOutput.additionalContext') \
    || fail "start after a compact failed"
  grep -qF STATE-MARKER-1751 <<<"$out" || fail "start after a compact did not print the saved state: $out"
  out=$(cd "$M" && CLAUDE_PROJECT_DIR=$M CONVEYOR_HOOK=1 bash "$SRC/foreman.sh" rules <<<"$inp") || fail "rules after a compact failed"
  grep -qF RULE-MARKER-1751 <<<"$out" || fail "rules after a compact did not print the rules: $out"
}

cases=(setup claim compact aftercompact)
# The cases CONVEYOR_SHELL_TEST_CASE names (comma-separated), as the runner selects them; all of them with none set.
SEL=${CONVEYOR_SHELL_TEST_CASE:-${cases[*]}}; SEL=${SEL//,/ }
for c in $SEL; do case " ${cases[*]} " in *" $c "*) ;; *) echo "unknown case $c" >&2; exit 2 ;; esac; done
read -ra cases <<<"$SEL"
for c in "${cases[@]}"; do (t_"$c" && : > "$B/$c.passed") > "$B/$c.out" 2>&1 & done
wait
. "$SRC/tests/casesreport-helper.sh"
casesreport "$B" cache- "${cases[@]}" || exit 1
echo "ok [foreman-cache]"
