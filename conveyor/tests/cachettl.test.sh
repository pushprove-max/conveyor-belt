#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases: a Claude call that runs without the card settings (--setting-sources "" and no --settings) gets the
# card settings' prompt cache lifetime, so it does not write its cache at the 1-hour price; a build session keeps the
# value of its own settings file. The step line's cacheFirst (the cache read and write of a session's first answer) is
# read, kept over the tries of a step, and passed by the record check.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# One issue, 7, with a stub claude that logs the prompt cache lifetime of each call (the one in its environment, and
# the one in the settings file it was given with --settings, if any) in $STUB/ttl, and answers with a result.
# The environment of the run names the 1-hour lifetime, as a Foreman session's does: a call that got none from the
# engine would write at that price.
ttlsetup() {
  setup "[$(issue 7 2026-01-01)]"; printf '%s\n' "$GO" > "$STUB/review.1"
  unset ANTHROPIC_BASE_URL ANTHROPIC_AUTH_TOKEN ANTHROPIC_API_KEY ENABLE_TOOL_SEARCH
  export CLAUDE_CODE_PROMPT_CACHE_TTL=1h
  # stub: the shared claude stub does not log its environment or the settings file it was given
  cat > "$STUB/claude" <<'EOF'
#!/usr/bin/env bash
cat > /dev/null; f=''
while [ $# -gt 0 ]; do [ "$1" != --settings ] || f=$2; shift; done
echo "env=${CLAUDE_CODE_PROMPT_CACHE_TTL:-unset} settings=$([ -z "$f" ] && echo none || jq -r '.env.CLAUDE_CODE_PROMPT_CACHE_TTL // "unset"' "$f")" >> "$STUB/ttl"
echo '{"type":"result","is_error":false,"result":"F1 DECLINE: wrong","num_turns":1,"usage":{"input_tokens":3,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":2}}'
EOF
  chmod +x "$STUB/claude"
}
# <commands>, run in the engine shell as `conveyor.sh run` makes it, with no loop run; their output is in $T/$CASE/out.
ttleng() {
  mkdir -p "$T/$CASE/cards"
  ( export CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards; . "$SRC/conveyor.sh" state-dir > /dev/null \
    && eval "$(grep '^\. "\$HERE/lib/' "$SRC/commands/run.sh")" && names && eval "$1" ) > "$T/$CASE/out" 2>&1
}
# <commands>: the one call they make logged env=5m, from the card settings, and no settings file of its own.
ttlone() {
  ttlsetup; ttleng "$1" || fail "the call failed: $(cat "$T/$CASE/out")"
  [ "$(cat "$STUB/ttl" 2>/dev/null)" = "env=5m settings=none" ] || fail "the call did not get the card settings' 5-minute cache lifetime: $(cat "$STUB/ttl" 2>&1) $(cat "$T/$CASE/out")"
}

# Bug: the findings judge ran with no cache lifetime and wrote 48M cache tokens at the 1-hour price.
t_ttljudge() { ttlone 'w=$CARDS/c7 && git -C "$MAIN" worktree add -q --detach "$w" && judgecall "$w" judge "F1 a finding"'; }
# Bug: the pick judge (askmodel()) wrote its cache at the 1-hour price.
t_ttlpick() { ttlone 'd=$T/$CASE/ask && mkdir -p "$d" && askmodel "$d" 60 low "" question'; }
# Bug: the Test page judge (a test action) wrote its cache at the 1-hour price.
t_ttltarun() {
  ttlone 'w=$CARDS/ta && mkdir -p "$w" "$TESTACTS" && tarun "{\"id\": \"tt1\", \"cli\": \"claude\", \"model\": \"m\", \"effort\": \"low\", \"action\": \"explain\"}" "$w" question'
}
# Bug: a Claude review wrote its cache at the 1-hour price.
t_ttlreview() {
  ttlone 'w=$CARDS/c7 && git -C "$MAIN" worktree add -q --detach "$w" && claudereview "$w" brief instructions m low'
}
# Bug: the start check of a seat wrote its cache at the 1-hour price.
t_ttlcheck() { ttlone 'startcheck "{\"seat\": \"reviewer\", \"cli\": \"claude\", \"model\": \"m\", \"account\": \"\"}"'; }
# Bug: the route check of a Claude seat (doctor, setup) wrote its cache at the 1-hour price.
t_ttlroute() { ttlone 'routecall claude m'; }
# The build session is given the 5-minute value by its settings file, not by the environment: the engine adds nothing
# to its environment, so the file's value is what it runs with.
t_ttlbuild() {
  ttlsetup; unset CLAUDE_CODE_PROMPT_CACHE_TTL
  ttleng 'w=$CARDS/c20260101T000000-r-7 && git -C "$MAIN" worktree add -q --detach "$w" && cardsettings "$w.settings" && session "$w" go' || fail "the build session failed: $(cat "$T/$CASE/out")"
  [ "$(cat "$STUB/ttl" 2>/dev/null)" = "env=unset settings=5m" ] || fail "the build session's cache lifetime is not the one of its settings file alone: $(cat "$STUB/ttl" 2>&1) $(cat "$T/$CASE/out")"
}
# What the step line's cacheFirst is: SESSIONREAD (jq/sessionread.jq) run on a session output, as session1() does.
cfread() { printf '%s\n' "$1" | jq -cRn --arg m m --arg e low --argjson s 1 "$(<"$SRC/jq/sessionread.jq")" | tail -n 1; }
cfans() { echo "{\"type\":\"assistant\",\"message\":{\"id\":\"$1\",\"model\":\"m\",\"usage\":{\"input_tokens\":1,\"output_tokens\":2,\"cache_read_input_tokens\":$2,\"cache_creation_input_tokens\":$3}}}"; }
CFRES='{"type":"result","is_error":false,"num_turns":2,"usage":{"input_tokens":2,"cache_creation_input_tokens":9,"cache_read_input_tokens":9,"output_tokens":4}}'
# Bug: the step line did not say how much cache the first answer read and wrote, so the share of a late Fix's write that
# the Build session had already written could not be measured. The second answer must not replace the first.
t_cachefirst() {
  local f; f=$(cfread "$(cfans a 20000 5000; cfans b 25000 700; echo "$CFRES")")
  [ "$(jq -c .cacheFirst <<<"$f")" = '{"read":20000,"write":5000}' ] || fail "cacheFirst is not the first answer's cache read and write: $f"
}
# Bug: a session with no answer that has usage got a cacheFirst of zeros, which reads as a first answer that used no cache.
t_cachefirstnone() {
  local f; f=$(cfread "$CFRES")
  jq -e 'has("cacheFirst") | not' <<<"$f" > /dev/null || fail "a session with no answer that has usage has a cacheFirst: $f"
  [ "$(jq -c .usage.read <<<"$f")" = 9 ] || fail "the line is not written as before: $f"
}
# Bug: a resumed or retried try wrote its own first answer over the first try's cacheFirst: the resumed one reads the
# whole earlier context, so it says nothing of what the session started from. Both folds of a step's tries (apitries()'s
# APIFOLD, a stall's BOTHTRIES) keep the first try's value.
t_cachefirstfold() {
  ttlsetup; local first later
  first=$(cfread "$(cfans a 20000 5000; echo "$CFRES")"); later=$(cfread "$(cfans b 90000 100; echo "$CFRES")")
  FIRST=$first LATER=$later ttleng 'jq -c --argjson p "$FIRST" "$APIFOLD" <<<"$LATER"; jq -c --argjson f "{\"reason\": \"stalled\", \"spent\": $FIRST}" "$BOTHTRIES" <<<"$LATER"' \
    || fail "the fold failed: $(cat "$T/$CASE/out")"
  [ "$(jq -c .cacheFirst "$T/$CASE/out" | sort -u)" = '{"read":20000,"write":5000}' ] || fail "a folded step line lost the first try's cacheFirst: $(cat "$T/$CASE/out")"
  [ "$(wc -l < "$T/$CASE/out")" = 2 ] || fail "a fold printed no line: $(cat "$T/$CASE/out")"
}
# Bug: the record check (jq/check.jq) did not know cacheFirst, so every step line that held it was refused and set aside:
# the build line was gone from the card's records. A whole cacheFirst passes; one that is not {read, write} numbers is refused.
t_cachefirstcheck() {
  local b='{"card":"c1","issue":1,"reason":"","result":"ok","sha":"","step":"build","time":"2026-11-01T00:00:00Z","tokens":{"claude":1,"codex":0}' bad
  bad=$(printf '%s\n' "$b,\"cacheFirst\":{\"read\":20000,\"write\":5000}}" "$b,\"cacheFirst\":{\"read\":\"x\",\"write\":5}}" "$b,\"cacheFirst\":{\"read\":1}}" "$b,\"cacheFirst\":[]}" \
    | jq -Rrn -f "$SRC/jq/check.jq") || fail "the record check did not run"
  [ "$(cut -f1 <<<"$bad" | tr '\n' ' ')" = '2 3 4 ' ] || fail "the check does not pass a whole cacheFirst (line 1) and refuse a text, a missing or a non-object one (lines 2 to 4); it refused: $bad"
}
