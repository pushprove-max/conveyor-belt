# SESSIONREAD in conveyor.sh: the fields of a session's line, from its stream-json output. Arguments: $m, $e, $s.
[inputs | fromjson? // empty | objects] as $all
  | def n: if type == "number" then . else 0 end;
    def add0: reduce .[] as $u ({input_tokens: 0, output_tokens: 0, cache_creation_input_tokens: 0, cache_read_input_tokens: 0, h: 0};
      .input_tokens += ($u.input_tokens | n) | .output_tokens += ($u.output_tokens | n)
      | .cache_creation_input_tokens += ($u.cache_creation_input_tokens | n) | .cache_read_input_tokens += ($u.cache_read_input_tokens | n)
      | .h += ([$u.cache_creation | objects | .ephemeral_1h_input_tokens] | first // 0 | n));
    def usable: (.input_tokens | type) == "number" and (.output_tokens | type) == "number";
    def answered: map(select(.type == "assistant" and (.message.usage | type) == "object" and (.message.id | type) == "string"))
      | group_by(.message.id) | map(last.message);
    def answers: answered | map(.usage);
  ([$all[] | .type] | rindex("result")) as $lr
  | [$all[] | select(.type == "result")] as $rs
  | ($rs | last // {}) as $r
  # The answers after the last result (all of them when there is none): a turn a timeout or a stop cut off.
  | (try (if $lr == null then $all else $all[($lr + 1):] end | answered | map(select(.usage | usable))) catch []) as $tailmsg
  | (try (([$rs[] | .usage | objects | select(usable)]) as $ru
      | ($tailmsg | map(.usage)) as $tail
      | if ($ru | length) == 0 and ($tail | length) == 0 then null else $ru + $tail | add0 end) catch null) as $u
  | ([$rs[] | select((.usage | type) != "object" or (.usage | usable | not))] | length) as $bad
  # The 1-hour cache writes of each model that ran, from its answers (each answer names its model): the result says
  # each model's cache writes, not which of them last an hour, and the hour rate is twice the 5-minute one.
  | (try ($all | answered | map(select((.model | type) == "string")) | group_by(.model)
      | map({key: .[0].model, value: (map([.usage.cache_creation | objects | .ephemeral_1h_input_tokens] | first // 0 | n) | add)}) | from_entries) catch null) as $h1
  # By model: the last result's modelUsage, plus the answers after it, each under the model it names (an
  # answer naming none under the model launched): a turn cut off after a result, or a session cut off before
  # its first, is priced at the models that ran it, and none of its tokens is left out of the split.
  | (try ((if ($r.modelUsage | type) == "object" then $r.modelUsage | with_entries(.value |= {input: (.inputTokens? | n),
          write: (.cacheCreationInputTokens? | n), read: (.cacheReadInputTokens? | n), output: (.outputTokens? | n)}) else {} end)
      | reduce $tailmsg[] as $a (.; (if ($a.model | type) == "string" and $a.model != "" then $a.model else $m end) as $k
          | .[$k] = ((.[$k] // {input: 0, write: 0, read: 0, output: 0}) | .input += ($a.usage.input_tokens | n) | .output += ($a.usage.output_tokens | n)
            | .write += ($a.usage.cache_creation_input_tokens | n) | .read += ($a.usage.cache_read_input_tokens | n)))
      # <synthetic> is what Claude Code names on a message no model answered (the note a cut-off session ends with): no model ran, and it has no price.
      | del(.["<synthetic>"])
      | if length == 0 then null
        else with_entries(.key as $k | .value += (if $h1 != null and ($h1[$k] | type) == "number" then {write1h: $h1[$k]} else {} end)) end) catch null) as $bm
  | {model: $m, effort: $e, sec: $s}
    + (if $u == null then {unread: (if ($all | length) == 0 then "the session output holds no event" else "the session output holds no token usage" end)}
       else {tokens: {claude: ($u.input_tokens + $u.cache_creation_input_tokens + $u.output_tokens)},
         usage: {input: $u.input_tokens, write: ($u.cache_creation_input_tokens - $u.h), write1h: $u.h, read: $u.cache_read_input_tokens, output: $u.output_tokens}}
         # A result whose usage cannot be read beside one that can: the usage kept is part of what the session used,
         # so the step is said unread (its tokens missing, unpriced) and keeps the part it has.
         + (if $bad > 0 then {unread: "\($bad) of \($rs | length) results hold no readable token usage, so the usage recorded is only part of it"} else {} end) end)
    + {stats: (try {
        turns: ([$rs[].num_turns | numbers] | if length == 0 then null else add end),
        apiSec: ([$rs[].duration_api_ms | numbers] | if length == 0 then null else max / 1000 | round end),
        tools: ([$all[] | select(.type == "assistant") | .message.content | arrays | .[] | objects | select(.type == "tool_use")]
          | (map(select(.id != null)) | unique_by(.id)) + map(select(.id == null)) | map(.name | strings) | group_by(.) | map({key: .[0], value: length}) | from_entries),
        refused: ([$rs[] | .permission_denials | arrays | length] | if length == 0 then null else add end),
        cacheHit: (if $u == null then null else $u.cache_read_input_tokens as $d | ($u.input_tokens + $u.cache_creation_input_tokens + $d) as $a
          | if $a > 0 then $d / $a * 1000 | round / 1000 else null end end),
        models: (if $bm == null then null else $bm | keys end), byModel: $bm} catch null),
       ok: ($r.is_error == false)}
