# OPENCODEREAD in session.sh: the fields of an OpenCode session's line, from its output (`opencode run --format json`:
# one event a line, each {type, timestamp, sessionID, part | error}), as SESSIONREAD gives a Claude session's.
# Arguments: $m, $s. A step (a step_finish event: one call of the model) holds that call's tokens, {input, output,
# reasoning, cache: {read, write}}, input without the cache, and its cost in dollars as OpenCode prices it. tokens is
# the fresh ones (input, cache writes, output and reasoning), under claude: the key of the sessions' tokens, whichever
# program runs them. usage is the split as a Claude session's (reasoning is output), with cost: OpenCode's dollars,
# left out when a step reports none, so the step is unpriced, never guessed. OpenCode reports no 1-hour cache writes
# (write1h 0) and no effort. ok: some step finished and no error event came.
[inputs | fromjson? // empty | objects] as $all
  | def n: if type == "number" then . else null end;
  [$all[] | select(.type == "step_finish") | .part | objects] as $st
  | ($st | map(.tokens | objects | {input: (.input | n), output: (((.output | n) // null) as $o | if $o == null then null else $o + (.reasoning | n // 0) end),
      read: (.cache.read? | n // 0), write: (.cache.write? | n // 0)})) as $tk
  | ($st | length) as $k
  | ([$tk[] | select(.input == null or .output == null)] | length + ($k - ($tk | length))) as $bad
  | ($tk | map(select(.input != null and .output != null))) as $ok
  | {input: ($ok | map(.input) | add // 0), write: ($ok | map(.write) | add // 0), read: ($ok | map(.read) | add // 0), output: ($ok | map(.output) | add // 0)} as $u
  | {model: $m, sec: $s}
    + (if ($ok | length) == 0 then {unread: (if ($all | length) == 0 then "the session output holds no event" else "the session output holds no token usage" end)}
       else {tokens: {claude: ($u.input + $u.write + $u.output)},
         usage: ({input: $u.input, write: $u.write, write1h: 0, read: $u.read, output: $u.output}
           + (if $bad == 0 and all($st[]; (.cost | type) == "number") then {cost: ($st | map(.cost) | add * 1000000 | round / 1000000)} else {} end))}
         + (if $bad > 0 then {unread: "\($bad) of \($k) steps hold no readable token usage, so the usage recorded is only part of it"} else {} end) end)
    + {stats: {turns: (if $k == 0 then null else $k end),
        tools: ([$all[] | select(.type == "tool_use") | .part.tool | strings] | group_by(.) | map({key: .[0], value: length}) | from_entries),
        cacheHit: (if ($ok | length) == 0 then null else ($u.input + $u.write + $u.read) as $a | if $a > 0 then $u.read / $a * 1000 | round / 1000 else null end end)},
       ok: ($k > 0 and all($all[]; .type != "error"))}
