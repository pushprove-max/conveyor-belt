# SPDX-License-Identifier: Apache-2.0
# One review, read-only, never running tests: of the staged diff, or as the third argument asks instead. It runs on
# Codex, on Claude when the reviewer in force is a Claude model (claudereview, below), or on OpenCode when it is an
# OpenCode one (opencodereview). A review and its judge run on the cores left for card work, as a build does
# (slot_keepwords, lib/slots.sh).
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
  [ "$n" != 2 ] || { echo "stalled twice at review: no progress since $(<"$1.stalled")$(keptnote "$u")"; return 1; }
  r=$(jq -r .reason <<<"$x"); printf '%s\n' "${r%%$'\n'*}; run again after ${REVIEW_PAUSE}s: $u"; return 1
}
review() { # <worktree> <brief> [instructions, in place of REVIEW]
  local model effort agent s rc ins=${3:-$REVIEW} br=$2 PROXY_ROLE=reviewer # the reviewer's route (proxyroute())
  newtexts ins; newtexts br # the new code's texts in place of the old code's, for a card that switched (newtexts(), lib/session.sh)
  s=$(seat reviewer) && jqget "$s" model model effort effort agent agent || { echo "the pack's models.allowed lists no reviewer model"; return 1; }
  rc=$(seatwait reviewer "$s" "$1" review) || { echo "$rc"; return 1; } # the CLI the seat names, never another; one gone for a moment is waited for
  rm -f "$1.review.new" "$1.spent"
  # A review of a change (its instructions begin with REVIEW, or REVIEWOFF, or FIXREVIEW for the review of a fix
  # alone) is told what not to raise; the check of an ALREADY-DONE claim (CONFIRM) lists what the issue still lacks,
  # and is not.
  [[ $ins != "$REVIEW"* && $ins != "$REVIEWOFF"* && $ins != "$FIXREVIEW"* ]] || ins+=$(donotraise)
  if [ "$agent" = claude ]; then apitries "$1" review "$1.events" claudereview "$1" "$br" "$ins" "$model" "$effort"
  elif [ "$agent" = opencode ]; then apitries "$1" review "$1.events" opencodereview "$1" "$br" "$ins" "$model" "$effort"
  else
    model=$(codexmodel "$model") || { echo "$model"; return 1; } # a family name, as the proxy lists it now
    apitries "$1" review "$1.events" codexreview "$1" "$br" "$ins" "$model" "$effort"
  fi; rc=$?
  # A `DECLINED:`, `MINOR:`, `OUTSIDE:` or `SELFHEALS:` line is the engine's alone to write (NOTFINDING): one the reviewer wrote is a finding, as
  # any line is.
  [ $rc != 0 ] || ! grep -Eq '^(DECLINED|MINOR|OUTSIDE|SELFHEALS):' "$1.review" 2>/dev/null \
    || { sed -E 's/^((DECLINED|MINOR|OUTSIDE|SELFHEALS):[[:space:]]*)+//' "$1.review" > "$1.review.new" && mv -f "$1.review.new" "$1.review"; } || { echo "the review could not be read"; return 1; }
  return $rc
}
# A failed Codex review's events, err and session file, copied to the card's kept folder ($ST/kept/<card>) as
# <card>.review.events, .err and .session (<card>.review-2.events and so on for a later review). Prints "; its events are
# kept in <name>" with the events file's name in that folder, or nothing when its events could not be kept (a reason
# that names the events file may point at the err file beside it: nostartsaid()). Fails when any of the three could not be
# copied: the caller then leaves the session file where Codex wrote it, as the only copy.
reviewkeep() { # <worktree> <session file, or "">
  local c=${1##*/} d n=1 b rc=0
  d=$ST/kept/$c; b=$c.review; while [ -e "$d/$b.events" ]; do n=$((n + 1)); b=$c.review-$n; done
  mkdir -p "$d" 2>/dev/null && cp "$1.events" "$d/$b.events" 2>/dev/null \
    || { echo "conveyor: card $c: a failed review's events could not be kept in $d" >&2; return 1; }
  # Bug: the err copy was in the events copy's chain, so an err that could not be copied (a full disk) dropped the note
  # of an events file already kept, and nostartsaid() said the words could not be kept. A part copy is removed: no err in
  # the kept folder tells nostartsaid() that the err was not kept.
  cp "$1.err" "$d/$b.err" 2>/dev/null || { rm -f "$d/$b.err"; echo "conveyor: card $c: a failed review's err could not be kept in $d" >&2; rc=1; }
  [ -z "$2" ] || cp "$2" "$d/$b.session" 2>/dev/null || { echo "conveyor: card $c: a failed review's session file could not be kept in $d" >&2; rc=1; }
  printf '; its events are kept in %s' "$b.events"; return $rc
}
# The note reviewkeep() printed (its last "; its events are kept in <name>") in a reason <text>, for a reason that replaces
# the review's own (a stall, or the API's refusal at each try): prints it, or nothing.
keptnote() { # <reason text>
  local n=${1##*; its events are kept in }
  [ "$n" != "$1" ] || return 0
  n=${n%%[;[:space:]]*}; printf '; its events are kept in %s' "$n"
}
# nostart()'s reason (NOSTART_WHY) with no word of the CLI's: its first line alone, naming the kept events or err file
# (reviewkeep()) where it pointed at "its words below": the CLI's words are in its events, or in its err when it wrote them
# to stderr alone. With no note (nothing was kept) it names the card's kept folder that could not hold them and, as the
# folder to make writable, the nearest one of it, kept or the state folder that is there, so staff have a step they can take.
# With no err beside the kept events file (its copy failed), it says the words are in the kept events file or only in the err
# that could not be kept: Codex can write a settings error to stderr alone, so the events file may not hold them.
nostartsaid() { # <reviewkeep()'s note> <worktree>
  local w=${NOSTART_WHY%%$'\n'*} k=kept/${2##*/} n=${1##*; its events are kept in } where='its words in the kept events or err file'
  if [ -n "$1" ]; then
    [ -e "$ST/kept/${n%.review*}/${n%.events}.err" ] || where='its words, in the kept events file or only in its err that could not be kept,'
    printf '%s%s' "${w//its words below/$where}" "$1"
  elif [[ $w == *'its words below'* ]]; then
    [ -d "$ST/$k" ] || k=kept; [ -d "$ST/$k" ] || k=''
    printf '%s; its words could not be kept in kept/%s in the state folder: make %sthe state folder writable, so that the next try keeps them' \
      "${w//its words below/its words}" "${2##*/}" "${k:+$k in }"
  else printf '%s' "$w"; fi
}
codexreview() { # <worktree> <brief> <instructions> <model> <effort>: one Codex review, ending as review() says
  local model=$4 effort=$5 rc roll s sec f run='' no='' kn=''
  rm -f "$1.review.new"; sec=$SECONDS; codexsb read-only
  (cd "$1" && codexargs && slot_keepwords && exec "${KEEP[@]}" timeout --kill-after=30 "$REVIEW_TIMEOUT" codex exec --json "${CODEX_SB[@]}" "${CODEX_PX[@]}" -m "$model" \
    -c "model_reasoning_effort=\"$effort\"" -o "$1.review.new" - <<<"$3"$'\n\n'"$2" > "$1.events" 2> "$1.err" 8>&-) &
  watch $! "$1.events" "$1.live" review "$model" "" "$effort"; rc=$?; sec=$((SECONDS - sec))
  # With no Codex sandbox (codexsb()), a write the review made is undone: the worktree is put back to the change it was given.
  [ "${CODEX_SB[0]}" = -s ] || { git -C "$1" restore -q --worktree -- . && git -C "$1" clean -fdq; } || { echo "the worktree could not be put back after the review"; return 1; }
  # The running total its session file holds: the tokens of a review that ended before its turn did.
  roll=$(rollout "$1.events"); [ -z "$roll" ] || { run=$(grep '"token_count"' "$roll" | tail -n 1 | jq -c '.payload.info.total_token_usage | objects' 2>/dev/null); }
  # Its seconds and, from its stream, its turns (turns completed) and its tool calls by kind (the items that
  # are not a message or reasoning).
  f=$(jq -cRn --arg m "$model" --arg e "$effort" --argjson s "$sec" --argjson run "${run:-null}" "$REVIEWREAD" "$1.events" 2>/dev/null | tail -n 1) \
    && [ -n "$f" ] || f=''
  if [ $rc = 0 ] && [ -s "$1.review.new" ] && mv -f "$1.review.new" "$1.review"; then
    rm -f "$roll"
    [ -n "$f" ] && jq -e '.stats.turns > 0' <<<"$f" >/dev/null && routed "$f" codex && return 0
    s="review reported no token usage"; [ "$(verdict "$1.review")" != none ] || no=2
  else
    # Its events, err and session file are kept, and the reason names the events file only: Codex's own words (which can
    # hold a credential in a URL) are never copied into a reason, as a reason goes to a GitHub comment.
    if kn=$(reviewkeep "$1" "$roll"); then rm -f "$roll"; fi; s="review failed ($(exitsaid "$rc" "$REVIEW_TIMEOUT"))$kn"
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
      s=$(nostartsaid "$kn" "$1"); f=$(PROXY_NOW=1 codexreview "$@"); no=$?
      [ $no != 0 ] || { printf '%s\n' "$f"; return 0; }
      bothsaid "$s" "$f"; return $no
    fi
    signinstop review; s=$(nostartsaid "$kn" "$1"); f=$(jq -c --argjson s "$NOSTART_START" '. + {start: $s}' <<<"$f")
  fi
  jq -c '{step: "review"} + .' <<<"$f" > "$1.spent"
  [ ! -e "$1.stalled" ] || { s="stalled at review: no progress since $(<"$1.stalled")$kn"; no=2; }
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
  # A review after a fix of review findings names that fix's diff in the card's fix rounds (donewhen.sh rereview()).
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
  cd "$1" && slot_keepwords && exec "${KEEP[@]}" timeout --kill-after=30 "$REVIEW_TIMEOUT" opencode run --pure --format json --agent conveyor-readonly -m "${2#opencode:}" --variant "$3"
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
  watch $! "$1.events" "$1.live" review "$4" "" "$5"; rc=$?; sec=$((SECONDS - sec)); rm -rf "$1.rv"
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
  (cd "$1" && proxyenv && cacheenv && acctrun "$d" && slot_keepwords && exec "${KEEP[@]}" timeout --kill-after=30 "$REVIEW_TIMEOUT" claude -p --model "$4" --effort "$5" --permission-mode default --tools Read,Grep,Glob \
    --setting-sources "" --strict-mcp-config --add-dir "$1.rv" --no-session-persistence --output-format stream-json --verbose \
    <<<"$p"$'\n\n'"$2" > "$1.events" 2> "$1.err" 8>&-) &
  watch $! "$1.events" "$1.live" review "$4" "" "$5"; rc=$?; sec=$((SECONDS - sec)); rm -rf "$1.rv"
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
# declined on this issue's cards (the declined list, DECLINED, holds them); the review after a fix round also gets the findings
# that round was told to fix, each with the judge's earlier reason when the judge gave a readable line for it (fixedbefore()). It marks each finding accepted, declined or
# outside (real, but not caused by the card's change), with a one-line reason, and declines a finding at any level (P0 to P3) only when its claim is wrong about the code, its proof cannot happen with what the project really runs, or its defect is already fixed on main ("rare case" is
# no reason, except at a level the control record's judgeRare names: judgeprompt(); a P3 is not declined for being minor). A declined finding becomes a line `DECLINED:
# <finding> (judge: <reason>)` of the review, which is no finding (NOTFINDING): it causes no fix round and no
# follow-up, and a review left with no finding is a GO; it goes to the declined list
# (declined(), by: "judge", why: the reason, kind: the kind the reason starts with, JUDGE, when it starts with one). An outside finding becomes a line `OUTSIDE: <finding> (judge: <reason>)`
# of the review, no finding either (no fix round for this card), and a JSON line {finding, reason} of
# <worktree>.outside, kept over the card's rounds (a later round's ruling of a finding replaces it, and one that is no
# longer outside, or goes to the self-heals list, leaves it): when the card lands, followups() files each as a follow-up of the
# card, as a NO-GO finding is filed. The review's record line holds judge: {model, effort, sec,
# tokens, usage, accepted: [{n, finding, place, reason, cost, effect}], declined: [{n, finding, place, reason, kind (when its reason starts with one)}], outside: [{n, finding, place, reason, effect}],
# selfheals: [{n, finding, place, reason, effect, cost (an accepted one's), outside (true for an OUTSIDE one)}] (below), back: the lines of the fix round's findings it was given, when it was given any, read: when the declined list it was given was read}; n is the
# finding's number as the judge was given it (its F<n>), and cost is what the judge wrote after "Cost to every card:",
# which every accepted finding the judge decided has: cost is null on a finding the judge gave no line for that could
# be read, which is kept in accepted for the fix round but is not accepted.
# Each finding reaches the judge marked with its place: inside the card's diff (any file:line it names, a path under the worktree read as one in it, is a
# line the staged change adds or changes, or one of the two lines a removal sits between, or its file is one the
# change deletes or changes as binary), outside it (an unchanged line beside a changed one too), or none (it
# names no file:line). One outside it is accepted when the card's change causes it, and answered OUTSIDE when it is real
# but the change did not cause it.
# The control record's judgeAlways (`control judge always <kind>...`) lists the finding kinds that are always accepted: the reviewer tags a finding of one with
# its kind right after its level (KINDS; the same word anywhere else in the finding is no tag), and a tagged finding is accepted whatever the judge says, wherever it is.
# The judge runs on the seat judgeseat() names (the reviewer's CLI too, when the control record sets it; left at
# default, another model family than the reviewer's), read-only, as a review does. A judge that
# cannot run or fails, or whose answer holds no decision line that is read, changes nothing: every finding is accepted, as
# with the judge off, and the line's judge says why (failed). No card is blocked by it. A decision line is read only when
# it parses whole, names a finding of the review, and is the only line that names it, and an accepted finding's line (an
# ACCEPT, or any answer for an always-accepted kind) holds a reason and its cost. Each finding with no such line is
# accepted (a line that names an unknown finding is dropped). An answer that is not read whole leaves the judge's line
# with failed, decided (the findings decided from it) and raw (its last 2,000 characters).
# Each accepted or outside finding also has its kind, effect (HARMRULE): what its failure does, never how likely it
# is. The reason starts with `harm:`, `self-heals:`, `cleanup:`, `already guarded:` or `docs drift:`; a reason with
# none leaves effect out, and such a finding is harm, so nothing is lost. A finding of another kind than harm whose
# Proof says it was seen in real logs or records is harm (SEENRX, lib/followups.sh), its reason saying so; so is an
# already-guarded one whose reason names no check found at a file:line of the worktree (guardless(), lib/followups.sh).
# A finding of a kind kept off the belt (LISTKINDS) outside the change, and on a follow-up card (its issue's body has
# a "Follow-up depth: N" line, N 1 or more: followups()) an accepted one, is written to its list (healsadd(),
# lib/followups.sh: the self-heals list, or the docs list for docs drift) in place of a follow-up or a fix round: it
# becomes a line `SELFHEALS: <finding> (judge: <kind>: <reason>)` of the review, no finding (NOTFINDING), in the line's
# selfheals. On a card that is no follow-up, so are the accepted findings of a review whose accepted findings are each
# of such a kind, at any review (HEALSEVERY); with a harm finding, or one with no kind, beside them, each accepted
# finding of a kind kept off the belt is fixed in the card's fix rounds as before; its effect goes to
# <worktree>.effects ({finding, effect, reason} a line, the last ruling of a finding kept), which afterreview() (lib/card.sh) reads at the last review, where it blocks no
# card, and followups() should it be left there. A finding of an always-accepted kind is harm whatever kind its
# reason gives, its reason saying so: it is never moved, and it blocks a card at its last review as any harm finding
# does. The lists keep the last ruling too: a finding an earlier round put on one that this round does not leaves it
# (healsunput()).
HARMRULE='Sort each finding you accept or mark outside by what its failure does, never by how likely it is:
- harm: data is lost or written wrong (card records, issues, kept work); wrong code lands or pushes, or a check
  passes that should fail; the belt or a card gets stuck and nothing recovers it without a person; a stop that
  nobody is told of; private text is published; a security hole.
- self-heals: the failure heals itself (a card waits longer, a step runs again, a slot is briefly over its cap);
  wrong or missing text that the next poll or turn corrects; extra work or cost, with no wrong result.
- cleanup: its fix changes no behaviour: an unused variable, a redundant check, a misleading name, a stale comment.
- already guarded: the finding is real, but another check in the code already stops the bad outcome; it names a
  missing second guard, not an open hole. The reason names that check as file:line; with none, it is harm.
- docs drift: a guide or README omits or misdescribes what the code does correctly.
A finding whose Proof says it was seen in real logs or records is harm, even when it heals itself. When you cannot
tell, it is harm.'
JUDGE='You are the judge of a code review. A reviewer read the staged change in this worktree (`git diff --cached`)
against the issue below and wrote the findings at the end of this message, numbered F1, F2 and so on. Decide for
each finding whether it counts: accept it, decline it, or mark it outside. Read the change and the code it touches;
do not run tests or builds and change nothing. Each finding is followed by the lines it cites, with a few around them,
and the staged change is given whole when it is small; read the rest of the change and the code by your tools. When
you cannot tell yet whether a claim is right or a proof can happen, read the code until you can: doubt alone is no
reason to decline.
Each finding is marked with its place: `inside the diff` (its file and line are in the staged change), `outside the
diff` (they are not) or `no place` (it names no file and line).
Answer OUTSIDE for a real defect that this card'"'"'s change did not cause: code the card neither changed nor broke.
The card lands without a fix for it, and the finding is filed as a follow-up of the card. A finding is real when
its proof can happen with what the project really runs and its claim is right. "Not about this card'"'"'s change" is
never a reason to decline a real finding: answer OUTSIDE for it.
Accept a finding only when all of these hold. One rule holds at every level, P0 to P3:
- It is inside the diff, or the card'"'"'s change causes it: a caller or dependant the change breaks. For one outside the
  diff, the reason names the changed line that causes it.
- Its proof can happen with what the project really runs: its real config, commands and inputs. Decline a proof that
  needs a stub built to misbehave, or a setup the project does not have.
<rare>
A finding that a test does not check what its name, its comment or the issue'"'"'s Done-when says it checks (it passes
with the behaviour broken) is a real defect at its level: "only a test gap" and "hypothetical" are no reason to
decline it.
A decline reason starts with its kind, then a colon and why: `claim wrong` (its claim is wrong about the code),
`cannot happen` (its proof cannot happen with what the project really runs), `fixed` (the defect is already fixed on
main), `rare case` (only where the rule above allows it), `not this change` or `other`.
A finding marked `[E<n>]` is the same finding back after its fix: the reviewer found it again after a fix session changed
the code for it. The findings that fix round was told to fix are listed before the findings, each with your earlier
reason for accepting it when you gave one that could be read (when there are any). A finding you accepted before is declined now only when the fix made it
untrue: the reason starts with `other` and says what the fix changed (`fixed` is for a defect already fixed on main). Otherwise judge it as the code stands.
A finding already declined (listed before the findings, each with the kind of its decline, when there are any) and
raised again with nothing new is declined as a repeat, with the earlier kind, only when that kind is `claim wrong`,
`cannot happen` or `fixed`, or the defect is fixed on main. When the earlier kind is `rare case`, `not this change`,
`other` or none, judge the finding again from the code, as a new finding.
Answer OUTSIDE for a real finding of any level that the change did not cause, also when its proof needs an uncommon
input or timing.
A finding marked `always accepted` is of a kind the project always accepts: answer ACCEPT for it. It is accepted
whatever you answer, so its line always ends with its `Cost to every card:`.
'"$HARMRULE"'
The reason of an ACCEPT or an OUTSIDE starts with that kind, `harm`, `self-heals`, `cleanup`, `already guarded` or
`docs drift`, then a colon.
Answer with exactly one line for each finding, in order, and no other line:
`F<n> ACCEPT: <harm | self-heals | cleanup | already guarded | docs drift>: <one-line reason>. Cost to every card: <any run, wait, retry or gate the fix would add to every card, or none>`
`F<n> DECLINE: <kind>: <one-line reason>`
`F<n> OUTSIDE: <harm | self-heals | cleanup | already guarded | docs drift>: <one-line reason: why it is real, and why this card'"'"'s change did not cause it>`
A reason that names another finding by its number quotes that finding'"'"'s file and line beside it, as
`F1 (src/a.js:12)`, so the reason reads on its own.
Write each reason in plain, short sentences: one idea in a sentence, common words, the active voice, no filler, no
praise and no hedging. Keep the form that these instructions give each line. Do not change the names of files,
commands, settings and functions.'
# JUDGE as the judge is given it: <rare> is its decline rule, by the control record's judgeRare (`control judge rare
# <level>...`, `control judge rare none`): with no level (the default, or a record that cannot be read), "rare case" is
# no reason to decline at any level; else it is one at the levels named, and at those only.
judgeprompt() {
  local l r
  l=$(ctl 2>/dev/null | jq -r '.judgeRare // [] | if length < 2 then join("") else "\(.[:-1] | join(", ")) and \(last)" end' 2>/dev/null) || l=''
  if [ -z "$l" ]; then
    r='Decline a finding at any level only when its claim is wrong about the code, its proof cannot happen with what the
project really runs, or its defect is already fixed on main. The reason says which of the three, and why. "Rare case" is no reason to decline at any level: an
unusual input, timing or setup that the project really runs is not one. A P3 is minor by its level: do not decline it
because it causes no wrong result.'
  else
    r="Decline a finding only when its claim is wrong about the code, its proof cannot happen with what the project
really runs, its defect is already fixed on main, or, at $l only, it is a rare case: its proof needs an input, timing or setup that the project runs
only rarely. The reason says which of these, and why; a rare-case reason starts with \"rare case\". At any other level,
\"rare case\" is no reason to decline: an unusual input, timing or setup that the project really runs is not one. A P3
is minor by its level: do not decline it because it causes no wrong result."
  fi
  printf '%s' "${JUDGE/<rare>/"$r"}"
}
# What the reviewer is told, after REVIEW, when the judge is on and always accepts some kinds.
KINDS='The project always accepts a finding of one of these kinds: <kinds>. A finding of one of them names its kind in
square brackets right after its level, as `[P1][<kind>] file:line what. Proof: <proof>`. Tag no other finding.'
# The findings of the review beside the worktree as the judge is given them, one JSON array: {n, finding, place:
# "inside", "outside" or "none", kind: the always-accepted kind it is tagged with, or null; an id mark of a finding
# that came back ([E2], REREVIEW) before or after its kind mark leaves it tagged}.
judgemarks() { # <worktree> <the always-accepted kinds, a JSON array>
  grep -Ev "$NOTFINDING" "$1.review" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//' | awk 'NF && !seen[$0]++' \
    | jq -cRn --argjson always "$2" --arg wt "$1/" --arg real "$(cd "$1" && pwd -P)/" --rawfile names <(git -C "$1" diff --cached --no-renames --name-only) \
      --rawfile hunks <(git -C "$1" diff --cached --no-renames -U0 | awk '/^diff --git / { h = 1; f = "" } h && /^\+\+\+ b\// { f = substr($0, 7); sub(/\t$/, "", f) }
        /^@@ / { h = 0; if (f != "") { split($3, a, ","); s = substr(a[1], 2) + 0; print f "\t" s "\t" s + (a[2] == "" ? 1 : a[2] == 0 ? 2 : a[2] + 0) - 1 } }') "$RX"'
      ($names | split("\n") | map(select(. != ""))) as $files
      | ($hunks | split("\n") | map(select(. != "") | split("\t") | {file: .[0], from: (.[1] | tonumber), to: (.[2] | tonumber)})) as $h
      | [inputs] | to_entries | map(.value as $l | ($l | split($wt) | join("") | split($real) | join("") | [scan("([A-Za-z0-9_./-]+):([0-9]+)")]) as $ws
        | {n: (.key + 1), finding: $l,
           place: (if ($ws | length) == 0 then "none"
             elif any($ws[]; (.[0] | ltrimstr("./")) as $p | (.[1] | tonumber) as $ln
               | any($files[]; . == $p) and (all($h[]; .file != $p) or any($h[]; .file == $p and .from <= $ln and $ln <= .to))) then "inside" else "outside" end),
           kind: ([$always[] | select(. as $k | $l | gsub("\\s*\\[E[0-9]+\\]"; "") | test("^\\[P[0-3]\\]\\[" + ($k | rx) + "\\]"; "i"))] | first)})'
}
# The lines each finding of a review cites, kept on the review's line (excerpts) so that the Board shows the lines the
# review read after the card's worktree is gone (history excerpts); a finding the judge declined (a DECLINED: line),
# found outside the change (an OUTSIDE: line) or wrote to the self-heals list (a SELFHEALS: line) keeps its lines too, as the Board lists it. A finding cites its first file:line or file:a-b,
# read as judgemarks() reads it (a path under the worktree read as one in it). The lines are read from git's trees only,
# never from the disk: the staged tree the review read (side "new") when it has the file and the first line; the tree
# of the worktree's HEAD (side "old"); and, for a review that follows a fix round, the tree before that fix (side
# "fix", the second argument). An older tree's lines are kept when no tree before it kept any for the citation, or
# when the cited lines, read as that tree's, take in lines the staged tree no longer has (git diff -U0 of that tree and
# the staged one): a citation of a line the change, or the fix, deleted keeps that line, beside the staged one when
# the staged file has a line at that number. A path that is not one in the repository (it starts with /, or has a . or
# .. part) gives nothing, as does a line that no tree has. Bounded: EXCERPTS excerpts, EXCERPTLINES cited lines each (with
# the fourth argument, that many lines more before and after them, from the first line that exists), each
# line cut to 300 characters. Prints a JSON array, [{at (the file and line as cited), side, from (the first line),
# lines}]; which review kept it is its line's (exdetail(), lib/donewhen.sh).
EXCERPTS=20 EXCERPTLINES=20
excerpts() { # <worktree> [<the tree before the fix round the review follows> [<the findings file, <worktree>.review when not given> [<lines kept before and after the cited ones, 0 when not given>]]]]
  local new old fix=${2:-} p a b at side t got del kept ra rb c=${4:-0} out='[]'
  new=$(git -C "$1" write-tree 2>/dev/null) || { echo '[]'; return 0; }
  old=$(git -C "$1" rev-parse -q --verify 'HEAD^{tree}' 2>/dev/null)
  while IFS=$'\t' read -r p a b; do
    [ "$(jq length <<<"$out")" -lt "$EXCERPTS" ] || break
    [[ $p =~ ^([A-Za-z0-9_.-]+/)*[A-Za-z0-9_.-]+$ ]] && [[ /$p/ != */../* && /$p/ != */./* ]] || continue
    at=$p:$a; [ -z "$b" ] || at+=-$b
    a=$((10#$a)); [ -n "$b" ] && b=$((10#$b)) && [ "$b" -ge "$a" ] || b=$a # 10#: a line cited as 08 is not octal
    [ "$a" -ge 1 ] || continue
    [ $((b - a)) -lt "$EXCERPTLINES" ] || b=$((a + EXCERPTLINES - 1))
    kept=0
    for side in new old fix; do
      case $side in new) t=$new ;; old) t=$old ;; fix) t=$fix ;; esac
      [ -n "$t" ] && [ "$(git -C "$1" cat-file -t "$t:$p" 2>/dev/null)" = blob ] || continue
      if [ "$side" != new ] && [ "$kept" = 1 ]; then
        # del: the cited lines, read as this tree's, take in a line the staged tree no longer has (a hunk's old side,
        # -<start>[,<count>]).
        del=$(git -C "$1" diff --no-ext-diff --no-color --no-renames -U0 "$t" "$new" -- "$p" 2>/dev/null | awk -v a="$a" -v b="$b" '
          /^@@ -/ { split(substr($2, 2), r, ","); n = (2 in r) ? r[2] + 0 : 1; if (n > 0 && r[1] <= b && r[1] + n - 1 >= a) d = 1 }
          END { print d + 0 }')
        [ "$del" = 1 ] || continue
      fi
      # awk reads to the end: one that stopped early would end git with SIGPIPE, which pipefail reads as a failure.
      ra=$((a > c ? a - c : 1)); rb=$((b + c))
      got=$(git -C "$1" cat-file blob "$t:$p" | awk -v a="$ra" -v b="$rb" 'NR >= a && NR <= b' | jq -Rnc '[inputs | .[0:300]]') || got='[]'
      [ "$got" = '[]' ] || [ "$(jq length <<<"$out")" -ge "$EXCERPTS" ] \
        || { kept=1; out=$(jq -c --arg at "$at" --arg s "$side" --argjson a "$ra" --argjson l "$got" '. + [{at: $at, side: $s, from: $a, lines: $l}]' <<<"$out"); }
    done
  done < <(sed -E 's/^(DECLINED|OUTSIDE|SELFHEALS):[[:space:]]*//' "${3:-$1.review}" 2>/dev/null | grep -Ev "$NOTFINDING" | jq -Rr --arg wt "$1/" --arg real "$(cd "$1" && pwd -P)/" \
    'split($wt) | join("") | split($real) | join("") | [scan("([A-Za-z0-9_./-]+):([0-9]{1,9})(?:[-–]([0-9]{1,9}))?")] | first // empty
      | [(.[0] | ltrimstr("./")), .[1], (.[2] // "")] | @tsv' | awk '!seen[$0]++')
  printf '%s\n' "$out"
}
# One judge call, read-only as a review is (claudereview(), codexreview(), opencodereview()): its answer in
# <worktree>.judge. Prints its fields as one JSON object, {model, effort, sec} and, when they can be read, tokens,
# usage and stats (turns, tool calls by name, models, as the review's line has them) (an OpenCode judge's holding its cost, usage.cost, when it reports one); one that fails prints them with failed (why) and fails.
# The check of a Fix hollow cases card (hollowproof(), lib/speedproof.sh) runs it on another seat: CALLSEAT, a seat as
# seat() prints it, with CALLSTEP and CALLACT the step and action its live record shows.
judgecall() { # <worktree> <instructions> <the brief and the findings>
  # shellcheck disable=SC2034 # PROXY_ROLE is read by proxyroute() in lib/control.sh
  local s=${CALLSEAT:-} model effort agent d p rc sec f='' roll run='' PROXY_ROLE=reviewer # the review's route (proxyroute())
  [ -n "$s" ] || s=$(judgeseat) || { jq -cn '{failed: "the control record names no judge, and the pack allows the review no model of another family than the reviewer runs on"}'; return 1; }
  jqget "$s" model model effort effort agent agent || model='' effort='' agent=''
  d=$(seatwait judge "$s" "$1" "${CALLSTEP:-review}") || { jq -cn --arg m "$model" --arg r "$d" '{model: $m, failed: $r}'; return 1; } # the CLI the seat names, never another; one gone for a moment is waited for
  rm -f "$1.judge" "$1.judge.events"
  jq -cn --arg m "$model" --arg e "$effort" --arg s "${CALLSTEP:-review}" --arg a "${CALLACT:-the judge reads the findings}" '{step: $s, at: (now | todate), last: null, turns: 0, model: $m, action: $a} + (if $e == "" then {} else {effort: $e} end)' > "$1.live.tmp" && mv -f "$1.live.tmp" "$1.live"
  sec=$SECONDS
  if [ "$agent" = claude ]; then
    # The card's review account, else its builder's; with no shell, the staged change is a file given to it alone.
    d=$(acctenv "${RACCT:-$ACCT}") || { jq -cn --arg r "$d" '{failed: $r}'; return 1; }
    rm -rf "$1.rv"; mkdir "$1.rv" && git -C "$1" diff --cached > "$1.rv/staged.diff" || { jq -cn '{failed: "the staged change could not be written for the judge"}'; return 1; }
    p=$2$'\n\n'"You have no shell: the staged change (\`git diff --cached\`) is the file $1.rv/staged.diff. Read it there, in parts if it is large."
    (cd "$1" && proxyenv && cacheenv && acctrun "$d" && slot_keepwords && exec "${KEEP[@]}" timeout --kill-after=30 "$REVIEW_TIMEOUT" claude -p --model "$model" --effort "$effort" --permission-mode default --tools Read,Grep,Glob \
      --setting-sources "" --strict-mcp-config --add-dir "$1.rv" --no-session-persistence --output-format stream-json --verbose \
      <<<"$p"$'\n\n'"$3" > "$1.judge.events" 2> "$1.judge.err" 8>&-); rc=$?; sec=$((SECONDS - sec)); rm -rf "$1.rv"
    f=$(jq -cRn --arg m "$model" --arg e "$effort" --argjson s "$sec" "$SESSIONREAD" "$1.judge.events" 2>/dev/null | tail -n 1 | jq -c '{model, effort, sec, tokens, usage, stats, ok} | del(.[] | nulls)' 2>/dev/null)
    [ $rc != 0 ] || { [ "$(jq -r .ok <<<"$f" 2>/dev/null)" = true ] \
      && jq -Rrn '[inputs | fromjson? // empty | objects | select(.type == "result")] | last | .result | strings' "$1.judge.events" > "$1.judge" 2>/dev/null; } || rc=1
    # Should a write get through all the same, the worktree is put back to the change the review read.
    git -C "$1" restore -q --worktree -- . && git -C "$1" clean -fdq || rc=1
    f=$(jq -c 'del(.ok)' <<<"$f" 2>/dev/null)
  elif [ "$agent" = opencode ]; then
    # Run as an OpenCode review is (ocrun()), with the staged change a file given to it alone.
    command -v opencode >/dev/null || { jq -cn --arg m "$model" '{model: $m, failed: "the judge is the OpenCode model \($m), and OpenCode (opencode) is not on PATH"}'; return 1; }
    rm -rf "$1.rv"; mkdir "$1.rv" && git -C "$1" diff --cached > "$1.rv/staged.diff" || { jq -cn '{failed: "the staged change could not be written for the judge"}'; return 1; }
    p=$2$'\n\n'"You have no shell: the staged change (\`git diff --cached\`) is the file $1.rv/staged.diff. Read it there, in parts if it is large."
    (ocrun "$1" "$model" "$effort" <<<"$p"$'\n\n'"$3" > "$1.judge.events" 2> "$1.judge.err" 8>&-); rc=$?; sec=$((SECONDS - sec)); rm -rf "$1.rv"
    [ $rc != 0 ] || jq -Rrn "$OPENCODEANSWER" "$1.judge.events" > "$1.judge" 2>/dev/null || rc=1
    git -C "$1" restore -q --worktree -- . && git -C "$1" clean -fdq || rc=1
    f=$(jq -cRn --arg m "$model" --arg e "$effort" --argjson s "$sec" "$OCREVIEWREAD" "$1.judge.events" 2>/dev/null | tail -n 1 | jq -c --arg m "$model" '{model, effort, sec, tokens, usage, stats} | if .stats then .stats.models = [$m] else . end | del(.[] | nulls)' 2>/dev/null)
  else
    model=$(codexmodel "$model") || { jq -cn --arg r "$model" '{failed: $r}'; return 1; }
    codexsb read-only
    (cd "$1" && codexargs && slot_keepwords && exec "${KEEP[@]}" timeout --kill-after=30 "$REVIEW_TIMEOUT" codex exec --json "${CODEX_SB[@]}" "${CODEX_PX[@]}" -m "$model" \
      -c "model_reasoning_effort=\"$effort\"" -o "$1.judge" - <<<"$2"$'\n\n'"$3" > "$1.judge.events" 2> "$1.judge.err" 8>&-); rc=$?; sec=$((SECONDS - sec))
    # With no Codex sandbox (codexsb()), the worktree is put back after the judge, as after an OpenCode one.
    [ "${CODEX_SB[0]}" = -s ] || { git -C "$1" restore -q --worktree -- . && git -C "$1" clean -fdq; } || rc=1
    roll=$(rollout "$1.judge.events"); [ -z "$roll" ] || { run=$(grep '"token_count"' "$roll" | tail -n 1 | jq -c '.payload.info.total_token_usage | objects' 2>/dev/null); rm -f "$roll"; }
    f=$(jq -cRn --arg m "$model" --arg e "$effort" --argjson s "$sec" --argjson run "${run:-null}" "$REVIEWREAD" "$1.judge.events" 2>/dev/null | tail -n 1 | jq -c --arg m "$model" '{model, effort, sec, tokens, usage, stats} | if .stats then .stats.models = [$m] else . end' 2>/dev/null)
  fi
  [ -n "$f" ] || f=$(jq -cn --arg m "$model" --arg e "$effort" --argjson s "$sec" '{model: $m, effort: $e, sec: $s}')
  [ $rc = 0 ] && [ -s "$1.judge" ] && { printf '%s\n' "$f"; return 0; }
  # Its login failed and the proxy is the reviewer's fallback: asked again at once through the proxy.
  ! loginfallback "$rc" "$agent" "$1.judge.events" "$1.judge.err" || { PROXY_NOW=1 judgecall "$@"; return; }
  jq -c --arg r "the judge call failed ($(exitsaid "$rc" "$REVIEW_TIMEOUT")), or gave no answer" '. + {failed: $r}' <<<"$f"; return 1
}
# The judge's message from its findings on (judged()): the whole staged change when it is under JUDGEDIFFLINES lines, then
# each finding of <worktree>.judge.marks with the lines it cites (excerpts(), as the Board shows them): the judge reads
# the rest of the diff (its file) and the code by its tools. A finding with no lines that can be read has none beside it.
# Each finding's lines come with JUDGECONTEXT lines before and after them, and, when <the tree before the last fix round>
# is given, the lines that fix deleted too, as the Board shows them. The replay (replay.sh) writes the marks file it reads.
JUDGEDIFFLINES=400 JUDGECONTEXT=3
judgefindings() { # <worktree> [<the tree before the last fix round>]
  local d m f ex
  d=$(git -C "$1" diff --cached 2>/dev/null) || d=''
  [ -z "$d" ] || [ "$(wc -l <<<"$d")" -ge "$JUDGEDIFFLINES" ] || printf '# The staged change (git diff --cached)\n%s\n\n' "$d"
  echo '# The findings'
  while IFS= read -r m; do
    jq -r '"F\(.n) [\({inside: "inside the diff", outside: "outside the diff", none: "no place"}[.place])\(if .kind then "; always accepted: \(.kind)" else "" end)] \(.finding)"' <<<"$m"
    f=$(jq -r .finding <<<"$m")
    ex=$(excerpts "$1" "${2:-}" <(printf '%s\n' "$f") "$JUDGECONTEXT") || ex='[]'
    jq -r '.[] | .from as $f | "  Lines at \(.at) (\({new: "the staged change", old: "the code before the change", fix: "the code before the last fix round"}[.side])):", (.lines | to_entries[] | "    \($f + .key): \(.value)")' <<<"$ex"
  done < <(jq -c '.[]' "$1.judge.marks")
}
# The findings the last fix round of the card was told to fix, each with its id and the reason the judge gave when it
# accepted it, none when the judge gave no readable line for it (the reason findings.jsonl keeps for the review that
# round fixed, donewhen.sh rounded(); a retried card's rounds come with its kept patch), as a section for the judge;
# nothing when no fix round has run. The reason is never looked up in the issue's review records: a newer one can be of
# a review after a test fix with no new round, and an older one of a patch `retry --fresh` discarded or, with issue 0,
# of another card.
fixedbefore() { # <worktree>
  [ -s "$1.rounds/findings.jsonl" ] || return 0
  jq -rs '([.[] | select(.tracked | not) | .round] | max) as $m
    | [.[] | select(.round == $m and (.tracked | not))
      | "- \(.id) \(.line)" + (if .reason then " (accepted: \(.reason))" else "" end)]
    | if length == 0 then empty else "# The findings the last fix round was told to fix", .[], "" end' "$1.rounds/findings.jsonl" 2>/dev/null
}
# The judge's already-guarded rulings in <worktree>.judge.said whose reason names no check found at a file:line of the
# worktree (guardless(), lib/followups.sh) become harm: the reason says so, and the finding goes to no list. Fails
# only when the file cannot be read or written again.
guardsaid() { # <worktree>
  local bad
  bad=$(jq -r '.d[] | select(.effect == "already guarded") | [.n, .reason] | map(tostring | gsub("[[:space:]]+"; " ")) | join("\t")' "$1.judge.said" | guardless "$1") || return 1
  [ "$bad" != '[]' ] || return 0
  jq -c --argjson b "$bad" --arg w "$GUARDLESS" '.d |= map(if .n | IN($b[]) then .effect = "harm" | .reason += $w | del(.heals) else . end) | '"$HEALSEVERY" "$1.judge.said" > "$1.judge.said.new" \
    && mv -f "$1.judge.said.new" "$1.judge.said"
}
# Each finding of the judge's decisions (<the decisions file>, judged()) marked heals is written to the list of its kind
# (healsadd(), lib/followups.sh), as a finding of <card> and <issue> in <area>. One whose entry cannot be written loses
# its mark and its kind, so it stays a finding with no kind (fixed or filed as harm is) and is not lost. Fails only when the file cannot be written again.
healsput() { # <card> <issue> <area> <the decisions file>
  local n e why f keep=()
  while IFS=$'\t' read -r n e why f; do
    healsadd "$1" "$2" "$3" "$why" "$f" review "$e" >/dev/null || { keep+=("$n"); echo "conveyor: card $1: a $e finding could not be written to its list, so it stays a finding: ${f:0:200}" >&2; }
  done < <(jq -r '.d[] | select(.heals) | [.n, .effect, .reason, .finding] | map(tostring | gsub("[[:space:]]+"; " ")) | join("\t")' "$4")
  [ ${#keep[@]} = 0 ] || { jq -c '($ARGS.positional | map(tonumber)) as $k | .d |= map(if .n | IN($k[]) then del(.heals, .effect) else . end) | '"$HEALSEVERY" "$4" --args "${keep[@]}" > "$4.new" && mv -f "$4.new" "$4"; }
}
# On a card that is no follow-up, the judge's parser (judged()) marks heals each accepted finding of a review whose
# accepted findings are each of a kind kept off the belt (LISTKINDS), and marks the decisions every. When one of them
# becomes harm (guardsaid()) or loses its kind (its list entry could not be written: healsput()), the review gives a fix
# round, and that round fixes its accepted findings as before: none keeps its mark, and healsunput() (judged()) takes
# off its list any entry this round wrote.
HEALSEVERY='if .every and any(.d[]; .accept and (.heals | not)) then .d |= map(if .accept then del(.heals) else . end) | del(.every) else . end'
# The entries an earlier review of <card> wrote to the self-heals list or the docs list (from: review) for the findings
# of the judge's decisions (<the decisions file>) that this round does not send to that list; with all, for each of its
# findings (its review stands as the reviewer wrote it). The last ruling of a finding stands, as in
# <worktree>.outside: one the judge now rules harm, gives no kind, finds in the change, declines or sends to the other
# list leaves the list, so it is never on two lists, or both on one and fixed or filed. An entry a batch card holds
# stays. Fails when a list cannot be written again.
healsunput() { # <card> <the decisions file> [all]
  local gone f
  for f in "$SELFHEALS" "$DOCSDRIFT"; do
    grep -qF "\"card\":$(jq -cn --arg c "$1" '$c')," "$f" 2>/dev/null || continue
    gone=$(jq -c --arg all "${3:-}" --arg docs "$([ "$f" = "$DOCSDRIFT" ] && echo 1)" "$HEALSONE"'[.d[]
      | select($all != "" or (.heals | not) or ((.effect == "docs drift") != ($docs != ""))) | .finding | one]' "$2" 2>/dev/null) || return 1
    [ "$gone" != '[]' ] || continue
    ( flock 9 || exit 1
      jq -c --arg c "$1" --argjson g "$gone" 'select(type != "object" or .card != $c or .from != "review" or .batched != null or (.finding | IN($g[]) | not))' "$f" > "$f.new" \
        && mv -f "$f.new" "$f" || { rm -f "$f.new"; exit 1; } ) 9>>"$f.lock" || return 1
  done
}
# The review of <worktree> stands as the reviewer wrote it (no judge, or a judge that failed: judged()), so no earlier
# round's ruling of its findings holds: each finding's kind leaves <worktree>.effects (with none, followups() files it
# as harm) and its entry leaves the self-heals list (healsunput()). Fails when either cannot be written again.
healsnone() { # <card> <worktree>
  local fs
  fs=$(leftovers "$2.review" | jq -Rcs 'split("\n") | map(select(. != ""))') || return 1
  [ "$fs" != '[]' ] || return 0
  [ ! -s "$2.effects" ] || { jq -c --argjson f "$fs" 'select(.finding | IN($f[]) | not)' "$2.effects" > "$2.effects.new" && mv -f "$2.effects.new" "$2.effects"; } || return 1
  healsunput "$1" <(jq -cn --argjson f "$fs" '{d: ($f | map({finding: .}))}') all
}
# The review beside the worktree, judged: prints the review's fields, with judge (above) when the judge was asked.
# It never fails: whatever goes wrong, the review stands as the reviewer wrote it.
judged() { # <card> <issue> <worktree> <brief> <the review's fields> [<the issue json> [<the tree before the last fix round>]]
  local wt=$3 ja before readat j why f back fu area stood=''
  ja=$(judgeon) && [ "$(verdict "$wt.review")" != none ] && grep -Evq "$NOTFINDING" "$wt.review" \
    || { healsnone "$1" "$wt" || echo "conveyor: cannot take the kinds an earlier judge gave the findings of $1 away" >&2; printf '%s\n' "$5"; return 0; }
  # fu: the card is a review follow-up (its issue's "Follow-up depth: N", N 1 or more); area: its issue's area label,
  # which its self-heals list entries keep.
  fu=$(jq -r '[.body // "" | match("(?:^|\n)Follow-up depth: ([0-9]{1,3})[ \t\r]*(?=\n|$)") | .captures[0].string | tonumber][0] // 0 | if . > 0 then "1" else "" end' <<<"${6:-null}" 2>/dev/null) || fu=''
  area=$(jq -r --arg p "$AREA" '.labels // [] | map(.name | select(startswith($p))) | .[0] // empty' <<<"${6:-null}" 2>/dev/null) || area=''
  # The findings already declined on this issue's cards, the last 50, each with its decline's kind (none on a line that
  # has no kind): one raised again with nothing new is declined again only after a kind JUDGE allows. readat: its time.
  readat=$(clock); before=$(stdb ask lines declined 2>/dev/null | jq -rR --arg c "$1" --argjson n "$2" --arg repo "$REPO" 'fromjson? | objects | select(.card == $c or (.issue == $n and $n != 0 and .repo == $repo))
    | "- \(.finding) (declined: \(.why)) [kind: \(.kind // "none")]"' 2>/dev/null | awk '!seen[$0]++' | tail -n 50)
  back=$(fixedbefore "$wt"); [ -z "$back" ] || back+=$'\n\n'
  if ! { judgemarks "$wt" "$ja" > "$wt.judge.marks" && jq -e 'length > 0' "$wt.judge.marks" > /dev/null; } 2>/dev/null; then
    j=$(jq -cn '{failed: "the findings could not be read for the judge"}'); stood=1
  elif [ -z "$before" ] || before="# Findings already declined on the cards of this issue"$'\n'"$before"$'\n\n'
    ! j=$(judgecall "$wt" "$(judgeprompt)" "$4"$'\n\n'"$back$before$(judgefindings "$wt" "${7:-}")"); then stood=1
  # What it said of each finding: its one decision line that parses whole, an accepted one with its reason and cost,
  # else the finding is accepted (a duplicate id, a line that cannot be read, no line). A line for no finding of the
  # review is dropped. A line's bullet or list number (`- `, `1. `, `1) `) is not read. None read at all fails the answer. An always-accepted kind beats a decline and an OUTSIDE.
  # An ACCEPT or OUTSIDE reason's leading kind (`harm:`, `self-heals:`, `cleanup:`, `already guarded:` or `docs drift:`)
  # is its effect, taken off the reason (HARMRULE); heals marks the ones that go to a list (above, and HEALSEVERY).
  elif ! jq -cn --slurpfile m "$wt.judge.marks" --rawfile a "$wt.judge" --arg seen "$SEENRX" --arg fu "$fu" --argjson k "$LISTKINDS" 'def rx: "^F(?<n>[0-9]+) (?<d>ACCEPT|DECLINE|OUTSIDE):[[:space:]]*(?<r>.*[^[:space:]].*)$";
      ($a | split("\n") | map(gsub("^([[:space:]`*-]|[0-9]+[.)])+|[[:space:]`*]+$"; "") | select(test("^F[0-9]+")))) as $said
      | ($said | map(capture(rx))) as $all
      | ($said | map(select([capture(rx)] | length == 0) | capture("^F(?<n>[0-9]+)").n | tonumber)) as $bad
      | ($m[0] | map(. as $x | [$all[] | select((.n | tonumber) == $x.n)] as $d
        | ((if ($d | length) == 1 and all($bad[]; . != $x.n) then $d[0] as $d
          | ($d.r | capture("^(?<r>.*?)[[:space:].;|,-]*Cost to every card:[[:space:]]*(?<c>.*[^[:space:]].*)$") // {r: $d.r, c: null}) as $rc
          | (if $d.d == "ACCEPT" then $rc.r elif $d.d == "OUTSIDE" then $d.r else "" end
            | capture("^(?<e>harm|self-heals|cleanup|already[ -]guarded|docs[ -]drift)[[:space:]]*:[[:space:]]*(?<r>.*[^[:space:]].*)$"; "i") // null
            | if . == null then null else .e |= (ascii_downcase | sub("^already-"; "already ") | sub("^docs-"; "docs ")) end) as $ek
          | ($ek != null and $ek.e != "harm" and ($x.finding | test($seen; "i"))) as $seenit
          | ($ek != null and $ek.e != "harm" and $x.kind != null) as $always
          | (if $ek == null then null elif $seenit or $always then "harm" else $ek.e end) as $e
          | (if $ek == null then null elif $seenit then $ek.r + " (its Proof says it was seen in real logs or records, so it is harm)"
             elif $always then $ek.r + " (it is a \($x.kind) finding, a kind the project always accepts, so it is harm)" else $ek.r end) as $er
          | if ($d.d == "ACCEPT" or $x.kind != null) and ($rc.c == null or $rc.r == "") then null
            else {n: $x.n, finding: $x.finding, place: $x.place}
              + (if $d.d == "ACCEPT" then {accept: true, reason: ($er // $rc.r), cost: $rc.c}
                 elif $x.kind != null then {accept: true, reason: "always accepted: a \($x.kind) finding (the judge \(if $d.d == "OUTSIDE" then "found it outside the change" else "declined it" end): \($rc.r))", cost: $rc.c}
                 elif $d.d == "OUTSIDE" then {accept: false, outside: true, reason: ($er // $d.r)}
                 else {accept: false, outside: false, reason: $d.r} + (($d.r | capture("^(?<k>claim wrong|cannot happen|fixed|rare case|not this change|other):"; "i") | {kind: (.k | ascii_downcase)}) // {}) end)
              + (if $e == null then {} else {effect: $e} end)
              + (if $e != null and $e != "harm" and $x.kind == null and ($d.d == "OUTSIDE" or $fu != "") then {heals: true} else {} end) end
          else null end)
          // {n: $x.n, finding: $x.finding, place: $x.place, accept: true, undecided: true, reason: "the judge gave no line for this finding that could be read", cost: null}))) as $s
      | ($fu == "" and any($s[]; .accept) and all($s[] | select(.accept); .effect | IN($k[]))) as $every
      | if all($s[]; .undecided) then error("none") else {whole: (all($s[]; .undecided | not) and ($all | length) == ($said | length) and ($said | length) == ($s | length)),
        d: (if $every then $s | map(if .accept then .heals = true else . end) else $s end)} + (if $every then {every: true} else {} end) end' > "$wt.judge.said" 2>/dev/null; then
    j=$(jq -c --rawfile r "$wt.judge" '. + {failed: "the answer of the judge holds no decision line that could be read", decided: 0, raw: ($r | .[-2000:])}' <<<"$j"); stood=1
  elif ! guardsaid "$wt" || ! healsput "$1" "$2" "$area" "$wt.judge.said"; then
    # The review stands as the reviewer wrote it, each finding a finding: none stays on the list (healsnone(), below).
    j=$(jq -cn '{failed: "the findings for the self-heals list could not be sorted from the answer of the judge"}'); stood=1
  # The review with each declined finding as a DECLINED line, each outside one as an OUTSIDE line and each one for a
  # list (the self-heals list or the docs list) as a SELFHEALS line; with no finding left, its verdict is GO.
  elif ! { jq -rRn --slurpfile d "$wt.judge.said" '($d[0].d | map(select((.accept | not) or .heals))) as $no | ($d[0].d | all((.accept | not) or .heals)) as $go
      | inputs | . as $l | gsub("^[[:space:]]+|[[:space:]]+$"; "") as $s | ([$no[] | select(.finding == $s)] | first) as $x
      | if $x then "\(if $x.heals then "SELFHEALS" elif $x.outside then "OUTSIDE" else "DECLINED" end): \($s) (judge: \(if $x.heals then "\($x.effect): " else "" end)\($x.reason))"
        elif $go and startswith("VERDICT:") then "VERDICT: GO" else $l end' "$wt.review" > "$wt.review.new" \
      && mv -f "$wt.review.new" "$wt.review"; } 2>/dev/null; then
    j=$(jq -c '. + {failed: "the review could not be written again with what the judge declined"}' <<<"$j"); stood=1
  else
    # A finding this round does not send to a list leaves it, as an earlier round put it there (healsunput()).
    healsunput "$1" "$wt.judge.said" || echo "conveyor: cannot take the findings of $1 that the judge no longer sorts for a list off that list" >&2
    # Each declined finding goes to the declined list (declined()), with its kind when its reason starts with one.
    while IFS=$'\t' read -r why f kind; do
      declined "$1" "$2" judge "$why" "$f" ${kind:+"$kind"} || echo "conveyor: cannot write the declined findings of $1 to the declined list" >&2
    done < <(jq -r '.d[] | select((.accept or .outside) | not) | [.reason, .finding, .kind // ""] | map(gsub("[[:space:]]+"; " ")) | join("\t")' "$wt.judge.said")
    # Each outside finding goes to <worktree>.outside, {finding, reason, effect} a line, once a finding: the card files them when it lands.
    # This round's ruling of a finding replaces an earlier round's: one this round sends to the list, or finds in the
    # change, leaves the file, so it is never both on the list and filed (tofile(), lib/followups.sh). One a batch card
    # holds already (an entry of this card with batched, healsbatch(), lib/heals.sh) leaves it too: the batch card fixes
    # it, so a later harm ruling files no second card for it.
    { [ ! -s "$wt.outside" ] && ! jq -e 'any(.d[]; .outside and (.heals | not))' "$wt.judge.said" >/dev/null 2>&1; } \
      || { { cat "$wt.outside" 2>/dev/null; jq -c --arg c "$1" --slurpfile b <(cat "$SELFHEALS" "$DOCSDRIFT" 2>/dev/null | jq -c 'objects | select(.batched != null) | {card, finding}' 2>/dev/null || :) \
          "$HEALSONE"'.d[] | {finding, reason, keep: (.outside and (.heals | not) and ({card: $c, finding: (.finding | one)} | IN($b[]) | not))} + if .effect then {effect} else {} end' "$wt.judge.said"; } \
        | jq -cs 'reduce .[] as $x ({}; .[$x.finding] = $x) | .[] | select(.keep != false) | del(.keep)' > "$wt.outside.new" && mv -f "$wt.outside.new" "$wt.outside"; } \
      || echo "conveyor: cannot write the findings of $1 that the judge found outside its change to $wt.outside" >&2
    # Each accepted finding's effect, the last ruling of a finding kept, for followups(); each self-heals one for the list, to the list.
    # A later ruling with no kind (or no longer accepted) removes the earlier one's effect: with no kind it is harm.
    { [ ! -s "$wt.effects" ] && ! jq -e 'any(.d[]; .accept and .effect and (.heals | not))' "$wt.judge.said" >/dev/null 2>&1; } \
      || { { cat "$wt.effects" 2>/dev/null; jq -c '.d[] | {finding, effect: (if .accept and (.heals | not) then .effect else null end), reason}' "$wt.judge.said"; } \
        | jq -cs 'reduce .[] as $x ({}; .[$x.finding] = $x) | .[] | select(.effect)' > "$wt.effects.new" && mv -f "$wt.effects.new" "$wt.effects"; } \
      || echo "conveyor: cannot write the kinds of the findings of $1 to $wt.effects; a finding with no kind is filed as harm" >&2
    j=$(jq -c --slurpfile d "$wt.judge.said" --rawfile r "$wt.judge" '$d[0] as $s | $s.d as $d | . + {accepted: ($d | map(select(.accept and (.heals | not)) | del(.accept, .outside, .undecided))), declined: ($d | map(select((.accept or .outside) | not) | del(.accept, .outside))),
      outside: ($d | map(select(.outside and (.heals | not)) | del(.accept, .outside)))} + (($d | map(select(.heals) | del(.accept, .heals))) as $h | if $h == [] then {} else {selfheals: $h} end)
      + (if $s.whole then {} else {failed: "the answer of the judge does not hold exactly one line for each finding and no other, each accepted one with its reason and cost", decided: ($d | map(select(.undecided | not)) | length), raw: ($r | .[-2000:])} end)' <<<"$j")
  fi
  # A review that stands as the reviewer wrote it: its findings keep no kind an earlier round gave them (healsnone()).
  [ -z "$stood" ] || healsnone "$1" "$wt" || echo "conveyor: cannot take the kinds an earlier judge gave the findings of $1 away" >&2
  rm -f "$wt.judge" "$wt.judge.marks" "$wt.judge.said" "$wt.judge.events" "$wt.judge.err" "$wt.review.new" "$wt.outside.new" "$wt.effects.new" "$wt.judge.said.new"
  # The judge's line keeps the findings of the last fix round it was given (back: fixedbefore()'s lines, with their
  # E<n> ids), which the judge replay (lib/replay.sh) gives its judge in turn: the rounds file is not kept with the records.
  # It keeps the declined lines it was given (before, [] for none) and when it read them (read, before seatwait()): a
  # decline made or replaced while the judge waited for its CLI is newer than the list it read, and replay leaves it out.
  jq -ce --slurpfile j <(printf '%s' "${j:-null}") --arg b "$back" --arg d "$before" --arg rd "$readat" '. + {judge: ($j[0] | if . == null then . else . + {before: ($d | split("\n") | map(select(startswith("- ")))), read: $rd} end
    | if $b == "" or . == null then . else . + {back: ($b | split("\n") | map(select(startswith("- "))))} end)}' <<<"$5" 2>/dev/null || printf '%s\n' "$5"
}
# The P3 findings the review still holds after the judge (judged()) are handled by the control record's rule P3 (the
# Rules tab). On, the default, each is a finding as a P2 is: it makes a NO-GO, goes to the fix round and, still open
# after the last review, is filed as a follow-up of the pack's P3 priority, or of none (followups()). Off, each becomes a line
# `MINOR: <finding>` of the review: listed on the card's review line and counted there (donewhen.sh counts()), but no finding
# (NOTFINDING): no fix round and no follow-up, and a review left with no finding is a GO. A finding's level is the
# first [P<n>] it names, as donewhen.sh counts() reads it. A review with no verdict is left as it is.
minor() { # <worktree>
  [ "$(ctl 2>/dev/null | jq -r '.rules.P3' 2>/dev/null)" = false ] && [ "$(verdict "$1.review")" != none ] || return 0
  jq -rRn --arg nf "$NOTFINDING" 'def p3: (test($nf) | not) and (capture("\\[(?<p>P[0-3])\\]").p // "P1") == "P3";
    [inputs] as $l | ($l | any(p3) and all(p3 or test($nf))) as $go
    | $l[] | if p3 then "MINOR: " + sub("^[[:space:]]+"; "") elif $go and startswith("VERDICT:") then "VERDICT: GO" else . end' "$1.review" > "$1.review.new" \
    && mv -f "$1.review.new" "$1.review" || { rm -f "$1.review.new"; echo "conveyor: the P3 findings of $1 could not be listed as minor; they count as findings" >&2; }
}
