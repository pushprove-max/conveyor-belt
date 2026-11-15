# SPDX-License-Identifier: Apache-2.0
# `conveyor.sh prices set <model> <input> <output> <cache read> | prices clear <model>`: one model price override of
# the pack (prices) saved, from the Board's Rules tab (Model prices). The prices are $ per million tokens, each a
# number of 0 or more; an override wins over the Board's built-in price of the model (dashboard_limit.py use_prices).
# clear takes the override off: the model has its built-in price again, or none. A bad value is refused with why,
# and the pack is left as it was. An OpenCode model is refused: its steps keep the cost OpenCode reports.
# Sourced by conveyor.sh.
. "$HERE/lib/prompts.sh" || exit 1
. "$HERE/lib/pick.sh" || exit 1
. "$HERE/lib/testfiles.sh" || exit 1
. "$HERE/lib/run.sh" || exit 1
. "$HERE/lib/machine.sh" || exit 1
. "$HERE/lib/install.sh" || exit 1
PRICES_USAGE='usage: conveyor.sh prices set <model> <input> <output> <cache read> | prices clear <model>'
priceset() { # set <model> <input> <output> <cache read> | clear <model>
  local why='' x n=0 names=(input output 'cache read') model='^[A-Za-z0-9][]A-Za-z0-9._:/@[-]{0,191}$'
  case ${1:-}:$# in set:5 | clear:2) ;; *) echo "$PRICES_USAGE" >&2; return 2 ;; esac
  # A model as the Board's MODEL takes it (dashboard_server.py): one word that starts with a letter or a digit.
  if ! [[ $2 =~ $model ]]; then why="\"$2\" is not a model name"
  elif [[ $2 == opencode:* ]]; then why="an OpenCode step keeps the cost OpenCode reports, so its model takes no price"; fi
  if [ "$1" = set ] && [ -z "$why" ]; then
    for x in "${@:3}"; do
      [[ $x =~ ^(0|[1-9][0-9]{0,5})(\.[0-9]{1,6})?$ ]] || { why="the ${names[n]} price is dollars per million tokens, a number of 0 or more (such as 3 or 0.25), not \"$x\""; break; }
      n=$((n + 1))
    done
  fi
  [ -z "$why" ] || { echo "conveyor: prices $1: $why; nothing changed" >&2; return 1; }
  case $1 in
    set) packset --arg m "$2" --argjson i "$3" --argjson o "$4" --argjson r "$5" '.prices[$m] = {input: $i, output: $o, cacheRead: $r}' ;;
    clear) packset --arg m "$2" 'if .prices[$m] == null then . else del(.prices[$m]) | if .prices == {} then del(.prices) else . end end' ;;
  esac
}
shift; priceset "$@"
