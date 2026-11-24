# SPDX-License-Identifier: Apache-2.0
# The defs the two folds of a step's tries share (TRYFOLD, lib/session.sh): APIFOLD (lib/session.sh) and BOTHTRIES
# (lib/review.sh) put them before their own program.
# add2 adds two objects' numbers. ranon: the models a try said ran it (stats.byModel, else stats.models).
# split: a try's own word on them ({byModel, models}). also($p): $p as an entry of alsoUsed ({model, usage, stats}).
# fold($p): this try's usage with that of $p, the two asked of one model, added. What must stay true: each try's tokens
# are priced at the models that try said ran it (the price table reads stats), never at the other try's. So the two
# splits by model are added when both give one, and the usage alone when both name the same one model or neither
# names any. A try that names none (a result the model API refused names no model) is taken to have run the one model
# the other names: the usage is added, priced at that model. Else $p's usage goes to alsoUsed with its own split, and
# unread says so (an estimate). When the usage alone is added at the one model and a try has a split by model, the
# other try's usage is added to that model's part of the split too (bmof): the price table prices a split of several
# models from the split alone, so a later try's split on another model would leave the first try's tokens out.
# took($p): $p's usage, with its split, in place of this try's, which read none.
def add2(a; b): [a, b] | map(. // {} | to_entries[]) | reduce .[] as $e ({}; .[$e.key] += $e.value);
def ranon: [.stats // {} | ((.byModel | objects | keys) // (.models | arrays) // [])[] | select(. != "<synthetic>")] | unique;
def split: .stats // {} | {byModel, models} | with_entries(select(.value != null));
def also($p): {model: $p.model, usage: $p.usage} + ($p | split | if . == {} then {} else {stats: .} end);
def addusage($p): .usage.cost as $c | .usage = (add2(.usage; $p.usage) | if [$c, $p.usage.cost] | all(type == "number") then . else del(.cost) end);
def addby($x; $y): reduce ($y | to_entries[]) as $e ($x; .[$e.key] = add2(.[$e.key]; $e.value));
# bmof($k): a try's split by model, or its usage as the part of $k, the one model it ran on (a split's write holds the
# 1-hour writes, which a usage keeps apart; sessionread.jq).
def bmof($k): if (.stats.byModel | type) == "object" then .stats.byModel
  else .usage // {} | {($k): ({input: (.input // 0), write: ((.write // 0) + (.write1h // 0)), read: (.read // 0), output: (.output // 0)}
    + (if (.write1h // 0) > 0 then {write1h} else {} end))} end;
# onemodel($p; $k): this try's usage with that of $p, both at the one model $k; the splits by model added when a try has one.
# With no model named ($k null), the usage alone is added.
def onemodel($p; $k): if $k != null and ([., $p] | any(.stats.byModel | type == "object")) then bmof($k) as $x | ($p | bmof($k)) as $y | addusage($p)
    | .stats = ((.stats // {}) | del(.byModel, .models)) + {byModel: addby($x; $y)} | .stats.models = (.stats.byModel | keys)
  else addusage($p) | if ranon == [] and $k != null then ($p | split) as $s | .stats = ((.stats // {}) | del(.byModel, .models)) + $s else . end end;
def fold($p): ranon as $a | ($p | ranon) as $b
  | if (.stats.byModel | type) == "object" and ($p.stats.byModel | type) == "object" then addusage($p)
      | .stats.byModel = addby(.stats.byModel; $p.stats.byModel)
      | .stats.models = (.stats.byModel | keys)
    elif ($a == $b and ($a | length) <= 1) or ([$a, $b] | map(length) | sort) == [0, 1] then onemodel($p; ($a + $b)[0])
    else ([$b, $a] | map(join(", ") | if . == "" then "none named" else . end)) as [$x, $y]
      | .unread //= "a try named other models that ran it (\($x)) than the other (\($y)): one split cannot price both" | .alsoUsed += [also($p)] end;
def took($p): .usage = $p.usage | ($p | split) as $s | if .stats == null and $s == {} then . else .stats = ((.stats // {}) | del(.byModel, .models)) + $s end;
