# CODEXREAD in session.sh: the fields of a Codex build, fix or rebase session's line, from its output (`codex exec
# --json`: one event a line, thread.started, turn.*, item.* and error), as SESSIONREAD gives a Claude session's.
# Arguments: $m, $e, $s, and $run: the running total the session file Codex keeps held (rollout()), null when none
# was read. A turn.completed event holds the turn's usage, {input_tokens (cache reads among them),
# cached_input_tokens, output_tokens (reasoning among them)}; a session cut off before its turn completed has none,
# and $run is taken instead. tokens is the fresh ones (input and output) under codex, as a Codex review's. usage is the
# split as a Claude session's: Codex reports no cache writes (write and write1h 0). turns are the items it completed
# (its messages, commands and file changes; not the notices Codex gives as error items), tools its commands, file
# changes and other calls by kind. ok: a turn completed, and no turn failed and no error event came.
[inputs | fromjson? // empty | objects] as $all
  | ($all | map(select(.type == "turn.completed") | .usage | objects)) as $t
  | (if ($t | length) > 0 then $t elif ($run | type) == "object" then [$run] else [] end) as $u
  | ([$all[] | select(.type == "item.completed") | .item.type // "item" | tostring | select(. != "error")]) as $it
  | {model: $m, effort: $e, sec: $s}
    + (if ($u | length) == 0 then {unread: (if ($all | length) == 0 then "the session output holds no event" else "the session output holds no token usage" end)}
       else ($u | {input: (map((.input_tokens // 0) - (.cached_input_tokens // 0)) | add), read: (map(.cached_input_tokens // 0) | add), output: (map(.output_tokens // 0) | add)})
         | {tokens: {codex: (.input + .output)}, usage: {input, write: 0, write1h: 0, read, output}} end)
    + {stats: {turns: ($it | length), tools: ($it | map(select(IN("agent_message", "reasoning", "item") | not)) | group_by(.) | map({key: .[0], value: length}) | from_entries)},
       ok: (($t | length) > 0 and all($all[]; .type != "turn.failed" and .type != "error"))}
