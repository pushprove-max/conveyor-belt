# SPDX-License-Identifier: Apache-2.0
# One review, read-only, never running tests: of the staged diff, or as the third argument asks instead. It runs on
# Codex, on Claude when the reviewer in force is a Claude model (claudereview, below), or on OpenCode when it is an
# OpenCode one (opencodereview). A review and its judge run at a session's lowered priority, as a build does
# (steer_words session, lib/slots.sh).
# Not --ephemeral: the session file Codex keeps is where a running review's tokens are read (rollout); it is
# removed when the review ends, however it ends.
# Answer in <worktree>.review; prints its record fields. A review that fails (a timeout, no answer) leaves the review
# before it where it was: those are still the card's last findings, and block() keeps and posts them. It fails with 2
# when it ended with no verdict (a non-zero exit, a timeout included, or an answer with neither a verdict nor token
# usage): reviewed() runs it again. One that wrote a verdict
# and then exited non-zero fails with 1: a verdict is never asked for twice. One the engine ended for making no progress
# (watch()) fails with 2 whatever it wrote: it did not end by itself, so what it wrote is not taken for its answer.
# Bug: a Codex review the model API refused (429 at every try) was run again once only, as one without a verdict is,
# and marked no API error, so the queue went on into the outage. It runs under apitries() as a Claude review does.
# A review that ends with no verdict (a non-zero exit, a timeout included, or an answer without one clear verdict) is
# most often a passing fault of the reviewer's network: the same review runs once more, after REVIEW_PAUSE, before the
# card blocks. The failed attempt is no review line of its own (the Board counts review lines as review rounds): it is
# firstTry, {reason, spent}, on the line after it, the review's or the blocked one's spent, whose tokens and usage hold
# both attempts' (when the first's usage is unknown or only part of it, or the seat's model changed between them, unread
# says so: one model prices the step's usage, so it is unpriced, never underpriced); an OpenCode review's
# cost (usage.cost) is the sum when both attempts report one, else none. A second failure fails with both
# reasons, side by side on its first line (block() keeps that line as the reason), the second's output after it; the
# first's is in firstTry. A review that answered, GO or NO-GO, never runs again.
# A review's record with its failed first attempt $f ({reason, spent}) folded in, as reviewed() and stopped() write it.
BOTHTRIES='def add2(a; b): [a, b] | map(. // {} | to_entries[]) | reduce .[] as $e ({}; .[$e.key] += $e.value);
  . + {firstTry: $f} | .tokens = add2(.tokens; $f.spent.tokens)
  | if $f.spent.model != null and $f.spent.model != .model then
      .unread //= "the first attempt ran on another model (\($f.spent.model)): one model cannot price both"
    elif (.usage | type) == "object" and ($f.spent.usage | type) == "object" then
      .usage.cost as $c | .usage = (add2(.usage; $f.spent.usage) | if [$c, $f.spent.usage.cost] | all(type == "number") then . else del(.cost) end)
      | if $f.spent.unread then .unread //= $f.spent.unread else . end
    else .unread //= ($f.spent.unread // "the token usage of the first attempt could not be read") end'
# A review that would read what the card's last review read is not run again. Each review line holds the card's staged
# change (patch, as cardpatch() gives it), the main commit the card sits on (main) and the hash of what the review is
# shown beside the diff, its commit trailers and D<n> lines (seen). When a review is due and all three
# equal those of the card's last review line, that review stands: its answer is still beside the worktree, and the
# loop takes it as if the review had returned it again (its verdict, its findings, the repeats and the round count).
# Prints the fields of that line: reused (the time of the review it reuses), its model and effort, and its usage at 0
# tokens, so the step is priced (at nothing); fails when there is no such review.
reusable() { # <card> <patch> <main> <seen>
  [ -n "$2" ] && [ -n "$3" ] && [ -n "$4" ] || return 1
  stdb ask lastreview "$1" 2>/dev/null | jq -ce --arg p "$2" --arg m "$3" --arg s "$4" 'select(.patch == $p and .main == $m and .seen == $s and (.result | IN("GO", "NO-GO")))
      | {reused: .time} + ({model, effort} | del(.[] | nulls)) + (if (.usage | type) == "object" then {usage: (.usage | map_values(0))} else {} end)' 2>/dev/null
}
reviewed() { # <worktree> <brief> [instructions]: prints and fails as review() does
  local t u rc x s r n=0
  rm -f "$1.stalled"; t=$(review "$@"); rc=$?
  if [ $rc = 0 ]; then
    [ "$(verdict "$1.review")" = none ] || { printf '%s\n' "$t"; return 0; }
    x=$(jq -c '{reason: "the review ended without one clear verdict", spent: .}' <<<"$t")
  elif [ $rc = 2 ]; then
    x=$(jq -cn --arg r "$t" --slurpfile s "$1.spent" '{reason: $r, spent: ($s[0] | del(.step))}' 2>/dev/null) || x=$(jq -cn --arg r "$t" '{reason: $r}')
  else printf '%s\n' "$t"; return 1; fi
  # A review that stalled (watch()) ended with no answer taken from it, a verdict it had written or not: it runs once
  # more as a review with no verdict does, and stalls on its line counts the stalls. Two stalls fail it, saying so.
  [ ! -e "$1.stalled" ] || n=1
  # The first attempt, kept from here until the review's line is written (began() drops it): a card stopped in the
  # pause records it alone (its events, read into it, go), one stopped in the second attempt records both. It is
  # .firsttry.new until its events are gone, so stopped() never reads them on top of it.
  printf '%s\n' "$x" > "$1.firsttry.new"; rm -f "$1.spent" "$1.events"; mv -f "$1.firsttry.new" "$1.firsttry"; sleep "$REVIEW_PAUSE"
  u=$(review "$@"); rc=$?
  [ $rc != 0 ] || [ "$(verdict "$1.review")" = none ] || { jq -c --argjson f "$x" --argjson n "$n" "$BOTHTRIES"' | if $n > 0 then .stalls = $n else . end' <<<"$u"; return 0; }
  [ $rc != 0 ] || { jq -c '{step: "review"} + .' <<<"$u" > "$1.spent"; u="the review ended without one clear verdict"; }
  [ ! -e "$1.stalled" ] || n=$((n + 1))
  s=$(jq -ce objects "$1.spent" 2>/dev/null) || s='{"step":"review"}'
  jq -c --argjson f "$x" --argjson n "$n" "$BOTHTRIES"' | if $n > 0 then .stalls = $n else . end' <<<"$s" > "$1.spent"
  [ "$n" != 2 ] || { echo "stalled twice at review: no progress since $(<"$1.stalled")"; return 1; }
  r=$(jq -r .reason <<<"$x"); printf '%s\n' "${r%%$'\n'*}; run again after ${REVIEW_PAUSE}s: $u"; return 1
}
review() { # <worktree> <brief> [instructions, in place of REVIEW]
  local model effort agent s rc ins=${3:-$REVIEW} PROXY_ROLE=reviewer # the reviewer's route (proxyroute())
  s=$(seat reviewer) && jqget "$s" model model effort effort agent agent || { echo "the pack's models.allowed lists no reviewer model"; return 1; }
  rc=$(seatready reviewer "$s") || { echo "$rc"; return 1; } # the CLI the seat names, never another
  rm -f "$1.review.new" "$1.spent"
  # A review of a change (its instructions begin with REVIEW, or REVIEWOFF, or FIXREVIEW for the review of a fix
  # alone) is told what not to raise; the check of an ALREADY-DONE claim (CONFIRM) lists what the issue still lacks,
  # and is not.
  [[ $ins != "$REVIEW"* && $ins != "$REVIEWOFF"* && $ins != "$FIXREVIEW"* ]] || ins+=$(donotraise)
  if [ "$agent" = claude ]; then apitries "$1" review "$1.events" claudereview "$1" "$2" "$ins" "$model" "$effort"
  elif [ "$agent" = opencode ]; then apitries "$1" review "$1.events" opencodereview "$1" "$2" "$ins" "$model" "$effort"
  else
    model=$(codexmodel "$model") || { echo "$model"; return 1; } # a family name, as the proxy lists it now
    apitries "$1" review "$1.events" codexreview "$1" "$2" "$ins" "$model" "$effort"
  fi; rc=$?
  # A `DECLINED:` or `MINOR:` line is the engine's alone to write (NOTFINDING): one the reviewer wrote is a finding, as
  # any line is.
  [ $rc != 0 ] || ! grep -Eq '^(DECLINED|MINOR):' "$1.review" 2>/dev/null \
    || { sed -E 's/^((DECLINED|MINOR):[[:space:]]*)+//' "$1.review" > "$1.review.new" && mv -f "$1.review.new" "$1.review"; } || { echo "the review could not be read"; return 1; }
  return $rc
}
codexreview() { # <worktree> <brief> <instructions> <model> <effort>: one Codex review, ending as review() says
  local model=$4 effort=$5 rc roll s sec f run='' no=''
  rm -f "$1.review.new"; sec=$SECONDS
  (cd "$1" && codexargs && steer_words session && exec "${STEER[@]}" timeout --kill-after=30 "$REVIEW_TIMEOUT" codex exec --json -s read-only "${CODEX_PX[@]}" -m "$model" \
    -c "model_reasoning_effort=\"$effort\"" -o "$1.review.new" - <<<"$3"$'\n\n'"$2" > "$1.events" 2> "$1.err" 8>&-) &
  watch $! "$1.events" "$1.live" review "$model"; rc=$?; sec=$((SECONDS - sec))
  # The running total its session file holds: the tokens of a review that ended before its turn did.
  roll=$(rollout "$1.events"); [ -z "$roll" ] || { run=$(grep '"token_count"' "$roll" | tail -n 1 | jq -c '.payload.info.total_token_usage | objects' 2>/dev/null); rm -f "$roll"; }
  # Its seconds and, from its stream, its turns (turns completed) and its tool calls by kind (the items that
  # are not a message or reasoning).
  f=$(jq -cRn --arg m "$model" --arg e "$effort" --argjson s "$sec" --argjson run "${run:-null}" "$REVIEWREAD" "$1.events" 2>/dev/null | tail -n 1) \
    && [ -n "$f" ] || f=''
  if [ $rc = 0 ] && [ -s "$1.review.new" ] && mv -f "$1.review.new" "$1.review"; then
    [ -n "$f" ] && jq -e '.stats.turns > 0' <<<"$f" >/dev/null && routed "$f" codex && return 0
    s="review reported no token usage"; [ "$(verdict "$1.review")" != none ] || no=2
  else s="review failed ($(exitsaid "$rc" "$REVIEW_TIMEOUT"))"$'\n'"$(tail -n 60 "$1.err")"
    [ "$(verdict "$1.review.new" 2>/dev/null)" != none ] || no=2; fi
  # A review that failed still spent its tokens and seconds: block() records them. One whose usage cannot be read
  # is recorded all the same, with its model, effort, seconds and stats and unread (why), so it is counted
  # among the unpriced steps instead of left out.
  [ -n "$f" ] || f=$(jq -cRn --arg m "$model" --arg e "$effort" --argjson s "$sec" '[inputs | fromjson? // empty] as $all
    | ([$all[] | select(.type == "item.completed") | .item.type // "item"]) as $it
    | {model: $m, effort: $e, sec: $s, unread: (if ($all | length) == 0 then "the review output holds no event" else "the review output holds no token usage" end),
       stats: {turns: ([$all[] | select(.type == "turn.completed")] | length),
         tools: ($it | map(select(IN("agent_message", "reasoning", "item") | not)) | group_by(.) | map({key: .[0], value: length}) | from_entries)}}' "$1.events" 2>/dev/null) \
    || f=$(jq -cn --arg m "$model" --arg e "$effort" --argjson s "$sec" '{model: $m, effort: $e, sec: $s, unread: "the review output could not be read"}')
  f=$(routed "$f" codex)
  # A review that never began its work, and wrote no verdict (no: 2), says why (nostart()). One whose own login failed,
  # with the proxy as the reviewer's fallback, runs again at once through the proxy (proxyfallback()).
  if [ "$no" = 2 ] && nostart "$rc" "$f" "$1.events" "$1.err" codex "$model" reviewer "" "$1"; then
    if proxyfallback codex; then
      s=$NOSTART_WHY; f=$(PROXY_NOW=1 codexreview "$@"); no=$?
      [ $no != 0 ] || { printf '%s\n' "$f"; return 0; }
      bothsaid "$s" "$f"; return $no
    fi
    signinstop review; s=$NOSTART_WHY; f=$(jq -c --argjson s "$NOSTART_START" '. + {start: $s}' <<<"$f")
  fi
  jq -c '{step: "review"} + .' <<<"$f" > "$1.spent"
  [ ! -e "$1.stalled" ] || { s="stalled at review: no progress since $(<"$1.stalled")"; no=2; }
  echo "$s"; return "${no:-1}"
}
# The prompt of a review with no shell (claudereview, opencodereview): its instructions, then where to read what a
# shell would show it, put in a folder beside the worktree (<worktree>.rv) given to it alone: the staged change, and
# the writing method (STE80, prompts.sh), the port's difference and the fix rounds when the brief names them; then the worktree's AGENTS.md, which Codex reads
# by itself. Fails, saying what could not be written.
noshell() { # <worktree> <brief> <instructions>
  local p
  rm -rf "$1.rv"; mkdir "$1.rv" && git -C "$1" diff --cached > "$1.rv/staged.diff" && cp "$STE80" "$1.rv/ste80.md" || { echo "the staged change or the writing method could not be written for the review"; return 1; }
  p=$3$'\n\n'"You have no shell: the staged change (\`git diff --cached\`) is the file $1.rv/staged.diff. Read it there, in parts if it is large. The file $STE80 is the file $1.rv/ste80.md: read it there."
  [ ! -e "$1.port" ] || { cp "$1.port" "$1.rv/port.diff" && p+=" The difference the review of a port reads (the file $1.port) is the file $1.rv/port.diff: read it there."; } \
    || { echo "the port's difference could not be written for the review"; return 1; }
  # A review after a fix of review findings names that fix's diff in the card's fix rounds (rereview()).
  [[ $2 != *"$1.rounds/"* ]] || { cp -R "$1.rounds" "$1.rv/rounds" && p+=" The files of the folder $1.rounds this review names are in the folder $1.rv/rounds: read them there."; } \
    || { echo "the fix rounds could not be written for the review"; return 1; }
  [ ! -f "$1/AGENTS.md" ] || p+=$'\n\n# AGENTS.md\n'"$(cat "$1/AGENTS.md")"
  printf '%s' "$p"
}
# One OpenCode run, a review's or the judge's, read-only: in the worktree, under REVIEW_TIMEOUT, its prompt on stdin
# and its events (--format json) on stdout; the model is OpenCode's <provider>/<model> and the effort its --variant,
# which a model with no such variant runs without. Every tool is denied but read, glob, grep and list (no edit or
# write, no shell, no web, no subagent), and so is every folder outside the worktree but <worktree>.rv (noshell()).
# Those permissions are the last config it reads, over the host's own, and it runs as an agent of its own
# (conveyor-readonly) holding them, named on its command line: an agent's permissions win over the global ones, so the
# host's default agent, or its own build agent, could allow writes. The worktree's own config (an opencode.json the
# change under review adds) is not read, nor are plugins (--pure). A headless run refuses any permission it asks.
ocrun() { # <worktree> <opencode:provider/model> <effort>
  local p
  p=$(jq -cn --arg rv "$1.rv/**" '{"*": "deny", read: "allow", glob: "allow", grep: "allow", list: "allow", external_directory: {"*": "deny", ($rv): "allow"}}') || return 1
  OPENCODE_CONFIG_CONTENT=$(jq -cn --argjson p "$p" '{permission: $p, default_agent: "conveyor-readonly", agent: {"conveyor-readonly": {mode: "primary", permission: $p}}}') || return 1
  export OPENCODE_CONFIG_CONTENT OPENCODE_DISABLE_PROJECT_CONFIG=1
  cd "$1" && steer_words session && exec "${STEER[@]}" timeout --kill-after=30 "$REVIEW_TIMEOUT" opencode run --pure --format json --agent conveyor-readonly -m "${2#opencode:}" --variant "$3"
}
# One OpenCode review, called by review() and ending as it does, run as claudereview() runs one: the same prompt,
# with no shell (noshell()), and the same answer file, record fields (OCREVIEWREAD's) and spent file. Its answer is the
# text of its last step that wrote any (OPENCODEANSWER). It runs read-only (ocrun()); should a write get through all
# the same, the worktree is put back to the change review() was given. With no opencode on PATH it fails, saying so.
opencodereview() { # <worktree> <brief> <instructions> <model> <effort>
  local rc sec f s p no=''
  command -v opencode >/dev/null || { echo "the reviewer is the OpenCode model $4, and OpenCode (opencode) is not on PATH: install it (npm install -g opencode-ai) and sign in to its providers (opencode auth login), or set another reviewer (conveyor.sh control reviewer)"; return 1; }
  p=$(noshell "$1" "$2" "$3") || { echo "$p"; return 1; }
  sec=$SECONDS
  (ocrun "$1" "$4" "$5" <<<"$p"$'\n\n'"$2" > "$1.events" 2> "$1.err" 8>&-) &
  watch $! "$1.events" "$1.live" review "$4"; rc=$?; sec=$((SECONDS - sec)); rm -rf "$1.rv"
  git -C "$1" restore -q --worktree -- . && git -C "$1" clean -fdq || { echo "the worktree could not be put back after the review"; return 1; }
  f=$(jq -cRn --arg m "$4" --arg e "$5" --argjson s "$sec" "$OCREVIEWREAD" "$1.events" 2>/dev/null | tail -n 1)
  jq -e objects <<<"$f" >/dev/null 2>&1 || f=$(jq -cn --arg m "$4" --arg e "$5" --argjson s "$sec" '{model: $m, effort: $e, sec: $s, unread: "the review output could not be read"}')
  if [ $rc = 0 ] && jq -Rrn "$OPENCODEANSWER" "$1.events" > "$1.review.new" 2>/dev/null && [ -s "$1.review.new" ] && mv -f "$1.review.new" "$1.review"; then
    jq -e 'has("tokens")' <<<"$f" >/dev/null && printf '%s\n' "$f" && return 0
    s="review reported no token usage"; [ "$(verdict "$1.review")" != none ] || no=2
  else
    # Its error events say why it ended (a provider's refusal, a model it does not know); its stderr, what else it said.
    s="review failed ($(exitsaid "$rc" "$REVIEW_TIMEOUT"))"$'\n'"$( { jq -Rrn '[inputs | fromjson? // empty | objects | select(.type == "error")
      | .error | (.data.message? // .message? // .name? // tostring) | strings] | .[-5:][]' "$1.events" 2>/dev/null; tail -n 60 "$1.err"; } )"
    jq -Rrn "$OPENCODEANSWER" "$1.events" > "$1.review.new" 2>/dev/null
    [ "$(verdict "$1.review.new")" != none ] || no=2; fi
  # A review that never began its work, and wrote no verdict (no: 2), says why (nostart()).
  [ "$no" != 2 ] || ! nostart "$rc" "$f" "$1.events" "$1.err" opencode "$4" reviewer "" "$1" \
    || { signinstop review; s=$NOSTART_WHY; f=$(jq -c --argjson s "$NOSTART_START" '. + {start: $s}' <<<"$f"); }
  jq -c '{step: "review"} + .' <<<"$f" > "$1.spent"
  [ ! -e "$1.stalled" ] || { s="stalled at review: no progress since $(<"$1.stalled")"; no=2; }
  echo "$s"; return "${no:-1}"
}
# One Claude review (a backup when Codex usage runs out), called by review() and ending as it does: the same
# instructions and brief, the same answer file, record fields and spent file, its stream read as a session's is
# (SESSIONREAD). It cannot change anything: its only tools are Read, Grep and Glob (no shell, no tool that edits or
# writes), it is given no settings, hooks or MCP servers, and its permission mode is default, so a headless session is
# refused whatever its tools do not allow. Should a write get through all the same, the worktree is put back to the
# change review() was given (everything is staged before a review): any file it changed or added is undone. With no shell it cannot run `git diff --cached`: the staged change is put
# in a folder beside the worktree, given to it alone. Codex reads AGENTS.md by itself; this review is given the
# worktree's, once, in its prompt, so both review against the same rules.
claudereview() { # <worktree> <brief> <instructions> <model> <effort>
  local rc sec f s p d no=''
  # The card's review account, else its builder's.
  d=$(acctenv "${RACCT:-$ACCT}") || { echo "$d"; return 1; }
  p=$(noshell "$1" "$2" "$3") || { echo "$p"; return 1; }
  sec=$SECONDS
  (cd "$1" && proxyenv && acctrun "$d" && steer_words session && exec "${STEER[@]}" timeout --kill-after=30 "$REVIEW_TIMEOUT" claude -p --model "$4" --effort "$5" --permission-mode default --tools Read,Grep,Glob \
    --setting-sources "" --strict-mcp-config --add-dir "$1.rv" --no-session-persistence --output-format stream-json --verbose \
    <<<"$p"$'\n\n'"$2" > "$1.events" 2> "$1.err" 8>&-) &
  watch $! "$1.events" "$1.live" review "$4"; rc=$?; sec=$((SECONDS - sec)); rm -rf "$1.rv"
  git -C "$1" restore -q --worktree -- . && git -C "$1" clean -fdq || { echo "the worktree could not be put back after the review"; return 1; }
  f=$(jq -cRn --arg m "$4" --arg e "$5" --argjson s "$sec" "$SESSIONREAD" "$1.events" 2>/dev/null | tail -n 1)
  jq -e 'objects | has("ok")' <<<"$f" >/dev/null 2>&1 \
    || f=$(jq -cn --arg m "$4" --arg e "$5" --argjson s "$sec" '{model: $m, effort: $e, sec: $s, unread: "the review output could not be read", ok: false}')
  proxypack; f=$(routed "$f")
  # The answer is the text of its last result, ending in one newline (verdict() reads the last line).
  if [ $rc = 0 ] && [ "$(jq -r .ok <<<"$f")" = true ] \
    && jq -Rrn '[inputs | fromjson? // empty | objects | select(.type == "result")] | last | .result | strings | sub("\\s+$"; "")' "$1.events" > "$1.review.new" 2>/dev/null \
    && [ -s "$1.review.new" ] && mv -f "$1.review.new" "$1.review"; then
    routedone 1
    jq -e 'has("tokens")' <<<"$f" >/dev/null && jq -c 'del(.ok)' <<<"$f" && return 0
    s="review reported no token usage"; [ "$(verdict "$1.review")" != none ] || no=2
  else s="review failed ($(exitsaid "$rc" "$REVIEW_TIMEOUT"))"$'\n'"$(tail -n 60 "$1.err")"
    jq -Rrn '[inputs | fromjson? // empty | objects | select(.type == "result")] | last | .result | strings | sub("\\s+$"; "")' "$1.events" > "$1.review.new" 2>/dev/null
    [ "$(verdict "$1.review.new")" != none ] || no=2; fi
  # A review that never began its work, and wrote no verdict (no: 2), says why (nostart()). One whose subscription
  # login failed, with the proxy as its fallback, runs again at once through the proxy (proxyfallback()).
  if [ "$no" = 2 ] && nostart "$rc" "$f" "$1.events" "$1.err" claude "$4" reviewer "${RACCT:-$ACCT}" "$1"; then
    routedone 0
    if proxyfallback; then
      s=$NOSTART_WHY; f=$(PROXY_NOW=1 claudereview "$@"); no=$?
      [ $no != 0 ] || { printf '%s\n' "$f"; return 0; }
      bothsaid "$s" "$f"; return $no
    fi
    signinstop review; s=$NOSTART_WHY; f=$(jq -c --argjson s "$NOSTART_START" '. + {start: $s}' <<<"$f")
  else routedone 1; fi
  jq -c '{step: "review"} + del(.ok)' <<<"$f" > "$1.spent"
  [ ! -e "$1.stalled" ] || { s="stalled at review: no progress since $(<"$1.stalled")"; no=2; }
  echo "$s"; return "${no:-1}"
}

# The judge. With the control record's judge on (`control judge on`; judgeon()), a judge reads each review of a card's change that holds findings, before
# the card acts on it: the findings, the card's staged change, the issue (the brief) and the findings already
# declined on this issue's cards (the declined list, DECLINED, holds them). It marks each finding accepted or declined, with a
# one-line reason, and declines unless the finding earns its place (a P2 has a higher bar: rare-case and style P2s are declined; a P3 is judged as a P2, but not declined for being
# minor). A declined finding becomes a line `DECLINED:
# <finding> (judge: <reason>)` of the review, which is no finding (NOTFINDING): it causes no fix round and no
# follow-up, and a review left with no finding is a GO; it goes to the declined list
# (declined(), by: "judge", why: the reason). The review's record line holds judge: {model, effort, sec,
# tokens, usage, accepted: [{n, finding, place, reason, cost}], declined: [{n, finding, place, reason}]}; n is the
# finding's number as the judge was given it (its F<n>), and cost is what the judge wrote after "Cost to every card:",
# which every accepted finding has.
# Each finding reaches the judge marked with its place: inside the card's diff (the first file:line it names, a path under the worktree read as one in it, is a
# line the staged change adds or changes, or one of the two lines a removal sits between, or its file is one the
# change deletes or changes as binary), outside it (an unchanged line beside a changed one too), or none (it
# names no file:line). One outside it is not dropped: the judge accepts it only when the card's change causes it.
# The control record's judgeAlways (`control judge always <kind>...`) lists the finding kinds that are always accepted: the reviewer tags a finding of one with
# its kind right after its level (KINDS; the same word anywhere else in the finding is no tag), and a tagged finding is accepted whatever the judge says, wherever it is.
# The judge runs on the seat judgeseat() names (the reviewer's CLI too, when the control record sets it; left at
# default, another model family than the reviewer's), read-only, as a review does. A judge that
# cannot run or fails, or whose answer is not read, changes nothing: every finding is accepted, as with the judge
# off, and the line's judge says why (failed). No card is blocked by it. An answer is read only when it holds exactly
# one decision line for each finding and none for any other, and each accepted finding's line (an ACCEPT, or either
# answer for an always-accepted kind) holds a reason and its cost.
JUDGE='You are the judge of a code review. A reviewer read the staged change in this worktree (`git diff --cached`)
against the issue below and wrote the findings at the end of this message, numbered F1, F2 and so on. Decide for
each finding whether it counts: accept it or decline it. Read the change and the code it touches; do not run tests
or builds and change nothing. Decline unless the finding earns its place; a tie is a decline. Accept a finding only
when all of these hold:
- It is about this card'"'"'s change. Each finding is marked with its place: `inside the diff` (its file and line
  are in the staged change), `outside the diff` (they are not) or `no place` (it names no file and line). Accept one
  outside the diff only when the card'"'"'s change causes it: a caller or dependant the change breaks. Decline one
  about code the card neither changed nor broke, with the reason `not about this card'"'"'s change`.
- Its proof can happen with what the project really runs: its real config, commands and inputs. Decline a proof that
  needs a stub built to misbehave, or a setup the project does not have.
- It is not a finding already declined (listed before the findings, when there are any) raised again with nothing new.
A P2 finding has a higher bar. Accept a P2 only when it is inside the diff, its proof uses what the project really
runs, and it would cause a wrong result that users or the next card meet. Decline with the reason `rare case` a P2
whose proof needs an unusual input, timing or setup. Decline with the reason `style` a P2 about wording, naming or
form that causes no wrong result.
Judge a P3 finding as a P2: accept it only when it is inside the diff, its proof uses what the project really runs,
and the defect is real, and decline a P3 whose proof needs an unusual input, timing or setup with the reason `rare
case`. A P3 is minor by its level: do not decline it because it causes no wrong result, or as `style` when it is a
misleading name or message, a small inconsistency, or dead code the change left.
A finding marked `always accepted` is of a kind the project always accepts: answer ACCEPT for it. It is accepted
whatever you answer, so its line always ends with its `Cost to every card:`.
Answer with exactly one line for each finding, in order, and no other line:
`F<n> ACCEPT: <one-line reason>. Cost to every card: <any run, wait, retry or gate the fix would add to every card, or none>`
`F<n> DECLINE: <one-line reason>`
A reason that names another finding by its number quotes that finding'"'"'s file and line beside it, as
`F1 (src/a.js:12)`, so the reason reads on its own.
'"$STE"
# What the reviewer is told, after REVIEW, when the judge is on and always accepts some kinds.
KINDS='The project always accepts a finding of one of these kinds: <kinds>. A finding of one of them names its kind in
square brackets right after its level, as `[P1][<kind>] file:line what. Proof: <proof>`. Tag no other finding.'
# The findings of the review beside the worktree as the judge is given them, one JSON array: {n, finding, place:
# "inside", "outside" or "none", kind: the always-accepted kind it is tagged with, or null}.
judgemarks() { # <worktree> <the always-accepted kinds, a JSON array>
  grep -Ev "$NOTFINDING" "$1.review" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//' | awk 'NF && !seen[$0]++' \
    | jq -cRn --argjson always "$2" --arg wt "$1/" --arg real "$(cd "$1" && pwd -P)/" --rawfile names <(git -C "$1" diff --cached --no-renames --name-only) \
      --rawfile hunks <(git -C "$1" diff --cached --no-renames -U0 | awk '/^diff --git / { h = 1; f = "" } h && /^\+\+\+ b\// { f = substr($0, 7); sub(/\t$/, "", f) }
        /^@@ / { h = 0; if (f != "") { split($3, a, ","); s = substr(a[1], 2) + 0; print f "\t" s "\t" s + (a[2] == "" ? 1 : a[2] == 0 ? 2 : a[2] + 0) - 1 } }') "$RX"'
      ($names | split("\n") | map(select(. != ""))) as $files
      | ($hunks | split("\n") | map(select(. != "") | split("\t") | {file: .[0], from: (.[1] | tonumber), to: (.[2] | tonumber)})) as $h
      | [inputs] | to_entries | map(.value as $l | ($l | split($wt) | join("") | split($real) | join("") | [scan("([A-Za-z0-9_./-]+):([0-9]+)")] | first) as $w
        | {n: (.key + 1), finding: $l,
           place: (if $w == null then "none" else ($w[0] | ltrimstr("./")) as $p | ($w[1] | tonumber) as $ln
             | if any($files[]; . == $p) and (all($h[]; .file != $p) or any($h[]; .file == $p and .from <= $ln and $ln <= .to)) then "inside" else "outside" end end),
           kind: ([$always[] | select(. as $k | $l | test("^\\[P[0-3]\\]\\[" + ($k | rx) + "\\]"; "i"))] | first)})'
}
# One judge call, read-only as a review is (claudereview(), codexreview(), opencodereview()): its answer in
# <worktree>.judge. Prints its fields as one JSON object, {model, effort, sec} and, when they can be read, tokens and
# usage (an OpenCode judge's holding its cost, usage.cost, when it reports one); one that fails prints them with failed (why) and fails.
judgecall() { # <worktree> <instructions> <the brief and the findings>
  # shellcheck disable=SC2034 # PROXY_ROLE is read by proxyroute() in lib/control.sh
  local s model effort agent d p rc sec f='' roll run='' PROXY_ROLE=reviewer # the review's route (proxyroute())
  s=$(judgeseat) || { jq -cn '{failed: "the control record names no judge, and the pack allows the review no model of another family than the reviewer runs on"}'; return 1; }
  jqget "$s" model model effort effort agent agent || model='' effort='' agent=''
  d=$(seatready judge "$s") || { jq -cn --arg m "$model" --arg r "$d" '{model: $m, failed: $r}'; return 1; } # the CLI the seat names, never another
  rm -f "$1.judge" "$1.judge.events"
  jq -cn --arg m "$model" '{step: "review", at: (now | todate), last: null, turns: 0, model: $m, action: "the judge reads the findings"}' > "$1.live.tmp" && mv -f "$1.live.tmp" "$1.live"
  sec=$SECONDS
  if [ "$agent" = claude ]; then
    # The card's review account, else its builder's; with no shell, the staged change is a file given to it alone.
    d=$(acctenv "${RACCT:-$ACCT}") || { jq -cn --arg r "$d" '{failed: $r}'; return 1; }
    rm -rf "$1.rv"; mkdir "$1.rv" && git -C "$1" diff --cached > "$1.rv/staged.diff" && cp "$STE80" "$1.rv/ste80.md" || { jq -cn '{failed: "the staged change or the writing method could not be written for the judge"}'; return 1; }
    p=$2$'\n\n'"You have no shell: the staged change (\`git diff --cached\`) is the file $1.rv/staged.diff. Read it there, in parts if it is large. The file $STE80 is the file $1.rv/ste80.md: read it there."
    (cd "$1" && proxyenv && acctrun "$d" && steer_words session && exec "${STEER[@]}" timeout --kill-after=30 "$REVIEW_TIMEOUT" claude -p --model "$model" --effort "$effort" --permission-mode default --tools Read,Grep,Glob \
      --setting-sources "" --strict-mcp-config --add-dir "$1.rv" --no-session-persistence --output-format stream-json --verbose \
      <<<"$p"$'\n\n'"$3" > "$1.judge.events" 2> "$1.judge.err" 8>&-); rc=$?; sec=$((SECONDS - sec)); rm -rf "$1.rv"
    f=$(jq -cRn --arg m "$model" --arg e "$effort" --argjson s "$sec" "$SESSIONREAD" "$1.judge.events" 2>/dev/null | tail -n 1 | jq -c '{model, effort, sec, tokens, usage, ok} | del(.[] | nulls)' 2>/dev/null)
    [ $rc != 0 ] || { [ "$(jq -r .ok <<<"$f" 2>/dev/null)" = true ] \
      && jq -Rrn '[inputs | fromjson? // empty | objects | select(.type == "result")] | last | .result | strings' "$1.judge.events" > "$1.judge" 2>/dev/null; } || rc=1
    # Should a write get through all the same, the worktree is put back to the change the review read.
    git -C "$1" restore -q --worktree -- . && git -C "$1" clean -fdq || rc=1
    f=$(jq -c 'del(.ok)' <<<"$f" 2>/dev/null)
  elif [ "$agent" = opencode ]; then
    # Run as an OpenCode review is (ocrun()), with the staged change a file given to it alone.
    command -v opencode >/dev/null || { jq -cn --arg m "$model" '{model: $m, failed: "the judge is the OpenCode model \($m), and OpenCode (opencode) is not on PATH"}'; return 1; }
    rm -rf "$1.rv"; mkdir "$1.rv" && git -C "$1" diff --cached > "$1.rv/staged.diff" && cp "$STE80" "$1.rv/ste80.md" || { jq -cn '{failed: "the staged change or the writing method could not be written for the judge"}'; return 1; }
    p=$2$'\n\n'"You have no shell: the staged change (\`git diff --cached\`) is the file $1.rv/staged.diff. Read it there, in parts if it is large. The file $STE80 is the file $1.rv/ste80.md: read it there."
    (ocrun "$1" "$model" "$effort" <<<"$p"$'\n\n'"$3" > "$1.judge.events" 2> "$1.judge.err" 8>&-); rc=$?; sec=$((SECONDS - sec)); rm -rf "$1.rv"
    [ $rc != 0 ] || jq -Rrn "$OPENCODEANSWER" "$1.judge.events" > "$1.judge" 2>/dev/null || rc=1
    git -C "$1" restore -q --worktree -- . && git -C "$1" clean -fdq || rc=1
    f=$(jq -cRn --arg m "$model" --arg e "$effort" --argjson s "$sec" "$OCREVIEWREAD" "$1.judge.events" 2>/dev/null | tail -n 1 | jq -c '{model, effort, sec, tokens, usage} | del(.[] | nulls)' 2>/dev/null)
  else
    model=$(codexmodel "$model") || { jq -cn --arg r "$model" '{failed: $r}'; return 1; }
    (cd "$1" && codexargs && steer_words session && exec "${STEER[@]}" timeout --kill-after=30 "$REVIEW_TIMEOUT" codex exec --json -s read-only "${CODEX_PX[@]}" -m "$model" \
      -c "model_reasoning_effort=\"$effort\"" -o "$1.judge" - <<<"$2"$'\n\n'"$3" > "$1.judge.events" 2> "$1.judge.err" 8>&-); rc=$?; sec=$((SECONDS - sec))
    roll=$(rollout "$1.judge.events"); [ -z "$roll" ] || { run=$(grep '"token_count"' "$roll" | tail -n 1 | jq -c '.payload.info.total_token_usage | objects' 2>/dev/null); rm -f "$roll"; }
    f=$(jq -cRn --arg m "$model" --arg e "$effort" --argjson s "$sec" --argjson run "${run:-null}" "$REVIEWREAD" "$1.judge.events" 2>/dev/null | tail -n 1 | jq -c '{model, effort, sec, tokens, usage}' 2>/dev/null)
  fi
  [ -n "$f" ] || f=$(jq -cn --arg m "$model" --arg e "$effort" --argjson s "$sec" '{model: $m, effort: $e, sec: $s}')
  [ $rc = 0 ] && [ -s "$1.judge" ] && { printf '%s\n' "$f"; return 0; }
  # Its login failed and the proxy is the reviewer's fallback: asked again at once through the proxy.
  ! loginfallback "$rc" "$agent" "$1.judge.events" "$1.judge.err" || { PROXY_NOW=1 judgecall "$@"; return; }
  jq -c --arg r "the judge call failed ($(exitsaid "$rc" "$REVIEW_TIMEOUT")), or gave no answer" '. + {failed: $r}' <<<"$f"; return 1
}
# The review beside the worktree, judged: prints the review's fields, with judge (above) when the judge was asked.
# It never fails: whatever goes wrong, the review stands as the reviewer wrote it.
judged() { # <card> <issue> <worktree> <brief> <the review's fields>
  local wt=$3 ja before j why f
  ja=$(judgeon) && [ "$(verdict "$wt.review")" != none ] && grep -Evq "$NOTFINDING" "$wt.review" \
    || { printf '%s\n' "$5"; return 0; }
  # The findings already declined on this issue's cards, the last 50: one raised again with nothing new is declined again.
  before=$(stdb ask lines declined 2>/dev/null | jq -rR --arg c "$1" --argjson n "$2" --arg repo "$REPO" 'fromjson? | objects | select(.card == $c or (.issue == $n and $n != 0 and .repo == $repo))
    | "- \(.finding) (declined: \(.why))"' 2>/dev/null | awk '!seen[$0]++' | tail -n 50)
  if ! { judgemarks "$wt" "$ja" > "$wt.judge.marks" && jq -e 'length > 0' "$wt.judge.marks" > /dev/null; } 2>/dev/null; then
    j=$(jq -cn '{failed: "the findings could not be read for the judge"}')
  elif [ -z "$before" ] || before="# Findings already declined on the cards of this issue"$'\n'"$before"$'\n\n'
    ! j=$(judgecall "$wt" "$JUDGE" "$4"$'\n\n'"$before# The findings"$'\n'"$(jq -r '.[]
      | "F\(.n) [\({inside: "inside the diff", outside: "outside the diff", none: "no place"}[.place])\(if .kind then "; always accepted: \(.kind)" else "" end)] \(.finding)"' "$wt.judge.marks")"); then :
  # What it said of each finding: exactly one decision line each and none for any other, an accepted one with its
  # reason and cost, else its answer is not read. An always-accepted kind beats a decline.
  elif ! jq -cn --slurpfile m "$wt.judge.marks" --rawfile a "$wt.judge" '($a | split("\n") | map(gsub("^[[:space:]`*-]+|[[:space:]`*]+$"; "") | select(test("^F[0-9]+")))) as $said
      | ($said | map(capture("^F(?<n>[0-9]+) (?<d>ACCEPT|DECLINE):[[:space:]]*(?<r>.*[^[:space:]].*)$"))) as $all
      | if ($all | length) != ($said | length) or ($all | length) != ($m[0] | length) then error("lines") else . end
      | $m[0] | map(. as $x | [$all[] | select((.n | tonumber) == $x.n)] as $d
        | if ($d | length) != 1 then error("F\($x.n)") else $d[0] as $d
          | ($d.r | capture("^(?<r>.*?)[[:space:].;|,-]*Cost to every card:[[:space:]]*(?<c>.*[^[:space:]].*)$") // {r: $d.r, c: null}) as $rc
          | if ($d.d == "ACCEPT" or $x.kind != null) and ($rc.c == null or $rc.r == "") then error("F\($x.n) cost") else . end
          | {n: $x.n, finding: $x.finding, place: $x.place}
            + (if $d.d == "ACCEPT" then {accept: true, reason: $rc.r, cost: $rc.c}
               elif $x.kind != null then {accept: true, reason: "always accepted: a \($x.kind) finding (the judge declined it: \($rc.r))", cost: $rc.c}
               else {accept: false, reason: $d.r} end) end)' > "$wt.judge.said" 2>/dev/null; then
    j=$(jq -c '. + {failed: "the answer of the judge does not hold exactly one line for each finding and no other, each accepted one with its reason and cost"}' <<<"$j")
  # The review with each declined finding as a DECLINED line; with no finding left, its verdict is GO.
  elif ! { jq -rRn --slurpfile d "$wt.judge.said" '($d[0] | map(select(.accept | not))) as $no | ($d[0] | all(.accept | not)) as $go
      | inputs | . as $l | gsub("^[[:space:]]+|[[:space:]]+$"; "") as $s | ([$no[] | select(.finding == $s)] | first) as $x
      | if $x then "DECLINED: \($s) (judge: \($x.reason))" elif $go and startswith("VERDICT:") then "VERDICT: GO" else $l end' "$wt.review" > "$wt.review.new" \
      && mv -f "$wt.review.new" "$wt.review"; } 2>/dev/null; then
    j=$(jq -c '. + {failed: "the review could not be written again with what the judge declined"}' <<<"$j")
  else
    # Each declined finding goes to the declined list (declined()).
    while IFS=$'\t' read -r why f; do
      declined "$1" "$2" judge "$why" "$f" || echo "conveyor: cannot write the declined findings of $1 to the declined list" >&2
    done < <(jq -r '.[] | select(.accept | not) | [.reason, .finding] | map(gsub("[[:space:]]+"; " ")) | join("\t")' "$wt.judge.said")
    j=$(jq -c --slurpfile d "$wt.judge.said" '. + {accepted: ($d[0] | map(select(.accept) | del(.accept))), declined: ($d[0] | map(select(.accept | not) | del(.accept)))}' <<<"$j")
  fi
  rm -f "$wt.judge" "$wt.judge.marks" "$wt.judge.said" "$wt.judge.events" "$wt.judge.err" "$wt.review.new"
  jq -ce --argjson j "${j:-null}" '. + {judge: $j}' <<<"$5" 2>/dev/null || printf '%s\n' "$5"
}
# The P3 findings the review still holds after the judge (judged()) are handled by the control record's rule P3 (the
# Rules tab). On, the default, each is a finding as a P2 is: it makes a NO-GO, goes to the fix round and, still open
# after the last review, is filed as a follow-up of the pack's P3 priority, or of none (followups()). Off, each becomes a line
# `MINOR: <finding>` of the review: listed on the card's review line and counted there (counts()), but no finding
# (NOTFINDING): no fix round and no follow-up, and a review left with no finding is a GO. A finding's level is the
# first [P<n>] it names, as counts() reads it. A review with no verdict is left as it is.
minor() { # <worktree>
  [ "$(ctl 2>/dev/null | jq -r '.rules.P3' 2>/dev/null)" = false ] && [ "$(verdict "$1.review")" != none ] || return 0
  jq -rRn --arg nf "$NOTFINDING" 'def p3: (test($nf) | not) and (capture("\\[(?<p>P[0-3])\\]").p // "P1") == "P3";
    [inputs] as $l | ($l | any(p3) and all(p3 or test($nf))) as $go
    | $l[] | if p3 then "MINOR: " + sub("^[[:space:]]+"; "") elif $go and startswith("VERDICT:") then "VERDICT: GO" else . end' "$1.review" > "$1.review.new" \
    && mv -f "$1.review.new" "$1.review" || { rm -f "$1.review.new"; echo "conveyor: the P3 findings of $1 could not be listed as minor; they count as findings" >&2; }
}
