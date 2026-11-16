# SPDX-License-Identifier: Apache-2.0
# `conveyor.sh prices ...`: the pack's model prices, added models and aliases (prices), saved from the Board's Rules
# tab (Model prices). The prices are $ per million tokens, each a number of 0 or more: input, output, cache read and,
# optionally, cache write (a 5-minute cache write; with none, 1.25 times input). They win over the Board's built-in
# price of the model (dashboard_limit.py use_prices), and an OpenCode model's price wins over the cost OpenCode reports.
#   set <model> <input> <output> <cache read> [<cache write>]   your price of a model, its name and aliases kept
#   clear <model>                                                 your price taken off: the built-in price again, or none
#   add <model> <provider> <name> <input> <output> <cache read> [<cache write>]
#                                                                 a model the table has not got, priced as a built-in
#   remove <model>                                                the model's entry taken out whole
#   name <model> [<name>]                                         its display name, or none (the ID is kept)
#   alias <model> add|remove <id>                                 another model ID that means the model
# An entry left with nothing is taken out, and so is prices with none. A bad value is refused with why, and the pack
# is left as it was. Sourced by conveyor.sh.
. "$HERE/lib/prompts.sh" || exit 1
. "$HERE/lib/pick.sh" || exit 1
. "$HERE/lib/testfiles.sh" || exit 1
. "$HERE/lib/run.sh" || exit 1
. "$HERE/lib/machine.sh" || exit 1
. "$HERE/lib/install.sh" || exit 1
PRICES_USAGE='usage: conveyor.sh prices set <model> <input> <output> <cache read> [<cache write>] | clear <model>
       | add <model> <claude|openai|opencode|other> <name> <input> <output> <cache read> [<cache write>] | remove <model>
       | name <model> [<name>] | alias <model> add|remove <id>'
# Drops an entry left empty, then prices when it has none.
PRICES_TIDY='if (.prices[$m] // {}) == {} then del(.prices[$m]) else . end | if .prices == {} then del(.prices) else . end'
priceset() {
  local why='' x n=0 names=(input output 'cache read' 'cache write') model='^[A-Za-z0-9][]A-Za-z0-9._:/@[-]{0,191}$' rates=() m=${2:-} w
  case ${1:-}:$# in set:5 | set:6 | clear:2 | add:7 | add:8 | remove:2 | name:2 | name:3 | alias:4) ;; *) echo "$PRICES_USAGE" >&2; return 2 ;; esac
  # A model as the Board's MODEL takes it (dashboard_server.py): one word that starts with a letter or a digit.
  [[ $m =~ $model ]] || why="\"$m\" is not a model ID"
  case $1 in
    set) rates=("${@:3}") ;;
    add) rates=("${@:5}")
      case $3 in claude | openai | opencode | other) ;; *) why=${why:-"the provider is claude, openai, opencode or other, not \"$3\""} ;; esac ;;
    alias)
      [ "$3" = add ] || [ "$3" = remove ] || why=${why:-"alias takes add or remove, not \"$3\""}
      [[ $4 =~ $model ]] || why=${why:-"\"$4\" is not a model ID"}
      [ "$4" != "$m" ] || why=${why:-"a model is not an alias of itself"} ;;
  esac
  # A display name: 1 to 60 characters with no control character, not all spaces.
  if [ "$1" = add ] || { [ "$1" = name ] && [ $# = 3 ]; }; then
    x=${3:-}; [ "$1" = add ] && x=$4
    [[ ${#x} -le 60 && $x =~ [^[:space:]] && ! $x =~ [[:cntrl:]] ]] || why=${why:-"a display name is 1 to 60 characters, not \"$x\""}
  fi
  if [ -z "$why" ]; then
    for x in "${rates[@]}"; do
      [[ $x =~ ^(0|[1-9][0-9]{0,5})(\.[0-9]{1,6})?$ ]] || { why="the ${names[n]} price is dollars per million tokens, a number of 0 or more (such as 3 or 0.25), not \"$x\""; break; }
      n=$((n + 1))
    done
  fi
  # An added model is one the pack has not got yet; an alias is no other model's ID or alias in the pack, and an added
  # model's ID no alias of one.
  if [ -z "$why" ] && { [ "$1" = add ] || [ "$1:${3:-}" = alias:add ]; }; then
    x=$4; [ "$1" = add ] && x=$m
    why=$(jq -r --arg m "$m" --arg a "$x" --arg op "$1" '.prices // {} | if $op == "add" and has($m) then "the pack has \($m) already"
      elif $op == "alias" and has($a) then "\($a) is a model of its own"
      else (to_entries | map(select(.key != $m and ((.value.aliases // []) | index($a)))) | first | if . then "\($a) is already an alias of \(.key)" else empty end) end' "$PACK") \
      || why="the pack does not read"
  fi
  [ -z "$why" ] || { echo "conveyor: prices $1: $why; nothing changed" >&2; return 1; }
  w=null; [ "${#rates[@]}" != 4 ] || w=${rates[3]}
  case $1 in
    set) packset --arg m "$m" --argjson i "$3" --argjson o "$4" --argjson r "$5" --argjson w "$w" \
      '.prices[$m] = ((.prices[$m] // {}) | del(.cacheWrite) + {input: $i, output: $o, cacheRead: $r} + (if $w == null then {} else {cacheWrite: $w} end))' ;;
    clear) packset --arg m "$m" "if .prices[\$m] == null then . else .prices[\$m] |= del(.input, .output, .cacheRead, .cacheWrite) | $PRICES_TIDY end" ;;
    add) packset --arg m "$m" --arg p "$3" --arg n "$4" --argjson i "$5" --argjson o "$6" --argjson r "$7" --argjson w "$w" \
      '.prices[$m] = {name: $n, provider: $p, input: $i, output: $o, cacheRead: $r} + (if $w == null then {} else {cacheWrite: $w} end)' ;;
    remove) packset --arg m "$m" "if .prices[\$m] == null then . else del(.prices[\$m]) | $PRICES_TIDY end" ;;
    name) packset --arg m "$m" --arg n "${3:-}" "if \$n == \"\" then (if .prices[\$m] == null then . else .prices[\$m] |= del(.name) | $PRICES_TIDY end)
      else .prices[\$m].name = \$n end" ;;
    alias) packset --arg m "$m" --arg a "$4" --arg op "$3" "if \$op == \"add\" then .prices[\$m].aliases = ((.prices[\$m].aliases // []) - [\$a] + [\$a])
      elif .prices[\$m] == null then . else .prices[\$m].aliases -= [\$a] | if .prices[\$m].aliases == [] then .prices[\$m] |= del(.aliases) else . end | $PRICES_TIDY end" ;;
  esac
}
shift; priceset "$@"
