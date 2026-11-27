# AGYREAD in lib/agy.sh: the fields of an agy session's line, from its output (`agy -p --output-format stream-json`:
# one event a line, {event, <its name>: {...}}), as OPENCODEREAD gives an OpenCode session's. Arguments: $m, $e, $s.
# effort is $e, the one agy was given (--effort), and left out when it was given none.
# The model is the one the init event names (agy names it there when --model is given), else $m. The usage is the last
# result event's (agy sums it over the turns): input_tokens holds the cache reads (cache_read_tokens) and
# output_tokens the thinking ones (total_tokens is input and output). tokens is the fresh ones (input less the cache
# reads, and output), under claude: the key of the sessions' tokens, whichever program runs them. usage is the split
# as a Claude session's, with no cost: agy reports none, so the step is unpriced, never guessed; agy reports no cache
# writes (write and write1h 0). stats: its turns (num_turns), its tool calls by tool (each tool step that
# ended) and the cache hit. ok: the result's status is SUCCESS. With no result, or one with no whole usage, unread says why.
[inputs | fromjson? // empty | objects] as $all
  | def n: if type == "number" then . else null end;
  ([$all[] | select(.event == "result") | .result | objects] | last) as $r
  | ($r.usage? | objects // null) as $u
  | (if $u == null then null else {in: ($u.input_tokens | n), out: ($u.output_tokens | n), read: ($u.cache_read_tokens | n // 0)} end) as $k
  | {model: ([$all[] | select(.event == "init") | .init.model? | strings] | last // $m), sec: $s} + (if $e == "" then {} else {effort: $e} end)
    + (if $r == null then {unread: (if ($all | length) == 0 then "the agy output holds no event" else "the agy output holds no result" end)}
       elif $k == null or $k.in == null or $k.out == null then {unread: "the agy result holds no whole token usage"}
       else ([$k.in - $k.read, 0] | max) as $i
         | {tokens: {claude: ($i + $k.out)}, usage: {input: $i, write: 0, write1h: 0, read: $k.read, output: $k.out}} end)
    + {stats: {turns: ($r.num_turns? | n),
        tools: ([$all[] | select(.event == "step_update") | .step_update | objects | select(.step_type == "tool" and .state == "DONE") | .tool_name | strings]
          | group_by(.) | map({key: .[0], value: length}) | from_entries),
        cacheHit: (if $k == null or ($k.in | n) == null or $k.in == 0 then null else $k.read / $k.in * 1000 | round / 1000 end)},
       ok: ($r.status? == "SUCCESS")}
