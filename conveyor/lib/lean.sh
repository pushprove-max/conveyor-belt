# SPDX-License-Identifier: Apache-2.0
# The lean settings (#1825), on the user's yes to setup's question (`setup --lean-settings yes|no`, commands/setup.md):
# in Claude Code's user settings, ${CLAUDE_CONFIG_DIR:-~/.claude}/settings.json (a link followed to its target),
# prompt suggestions and away summaries off and each skill's description in the skill listing capped (LEANKEYS); in
# Serena's config, ${SERENA_HOME:-~/.serena}/serena_config.yml when it is there, its web dashboard off. Card sessions
# read neither file (they start with --setting-sources "" and Serena's dashboard off on its command line): this is for
# the user's own sessions.
# The record, one per machine (leanrec): {answer: yes|no, added: the keys Conveyor wrote, claude and serena: the two
# files as they were named when written (leanpath), at: the UTC time it was last written}. A key is written only when
# it is absent and not in added, so a key the user set is never changed, and a key the user removed after Conveyor
# wrote it stays removed. Loaded when first needed by install() (lib/install.sh),
# which runs leansettings after it installs a new commit, so each engine update writes again only the keys never
# written, and by setup() and doctor() (lib/setup.sh).
LEANKEYS='[{"key": "env.CLAUDE_CODE_ENABLE_PROMPT_SUGGESTION", "path": ["env", "CLAUDE_CODE_ENABLE_PROMPT_SUGGESTION"], "value": "false"},
  {"key": "env.CLAUDE_CODE_ENABLE_AWAY_SUMMARY", "path": ["env", "CLAUDE_CODE_ENABLE_AWAY_SUMMARY"], "value": "0"},
  {"key": "skillListingMaxDescChars", "path": ["skillListingMaxDescChars"], "value": 400}]'
LEANSERENA=serena:web_dashboard
# Serena's web_dashboard line with the value <true|false>, any spaces and a comment after it kept (sed -E: \1 the
# key, \2 what follows the value).
leandash() { echo "^(web_dashboard:[[:space:]]*)$1([[:space:]]*(#.*)?)\$"; }
leanrec() { echo "${XDG_DATA_HOME:-$HOME/.local/share}/conveyor/lean-settings.json"; }
# The <claude|serena> file, as named: the record's while its added names a key of that file, so an update, an undo
# and doctor read the file the keys were written to whatever CLAUDE_CONFIG_DIR or SERENA_HOME is then (an undo under
# another one would take the user's own value from a file Conveyor never wrote); else the one the environment names.
leanpath() { # <claude|serena>
  jq -er --arg f "$1" --arg s "$LEANSERENA" 'if (.added | arrays | any(.[]; strings | (. == $s) == ($f == "serena"))) then .[$f] | strings else empty end' \
    "$(leanrec)" 2>/dev/null \
    || case $1 in claude) echo "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json" ;; *) echo "${SERENA_HOME:-$HOME/.serena}/serena_config.yml" ;; esac
}
leanclaudef() { p_realpath "$(leanpath claude)"; }
leanserenaf() { p_realpath "$(leanpath serena)"; }
# Runs <command> with the record's lock held: two engine updates of this machine at once, or one beside setup, would
# each read the settings file and write it whole, and the second write would lose the first one's keys.
leanlocked() { # <command> [args]
  local r; r=$(leanrec) && mkdir -p "${r%/*}" || return 1
  ( flock -w 60 9 || { echo "conveyor: the lean settings' lock $r.lock was held for 60 s; the lean settings were not changed" >&2; exit 1; }
    "$@" ) 9>>"$r.lock"
}
# Whether <file> is one JSON object, the one shape a settings file is written back as (an empty file, or two values
# one after the other, is not).
leanjson() { jq -se 'length == 1 and (.[0] | type == "object")' "$1" >/dev/null 2>&1; }
leanadded() { jq -c '.added | arrays | map(strings)' "$(leanrec)" 2>/dev/null || echo '[]'; }
# The files are named as leanpath names them before this write: the files the keys were just written to or taken from.
leanput() { # <answer> <added keys, JSON>
  local r t c s; r=$(leanrec); c=$(leanpath claude); s=$(leanpath serena); t=$(mktemp "$r.XXXXXX") || return 1
  jq -n --arg a "$1" --argjson k "$2" --arg c "$c" --arg s "$s" '{answer: $a, added: ($k | unique), claude: $c, serena: $s, at: (now | todate)}' > "$t" && mv "$t" "$r" \
    || { rm -f "$t"; echo "conveyor: the lean settings' record $r could not be written" >&2; return 1; }
}
# <file> written by <command> [args] (its output is the file's new text), kept whole: copied first to
# <file>.conveyor-<UTC time>.bak, written beside it with the file's mode and moved in.
leanwritef() { # <file> <command> [args]
  local f=$1 t; shift
  [ ! -e "$f" ] || cp -p "$f" "$f.conveyor-$(date -u +%Y%m%dT%H%M%SZ).bak" || return 1
  mkdir -p "${f%/*}" && t=$(mktemp "$f.XXXXXX") || return 1
  { [ ! -e "$f" ] || cp -p "$f" "$t"; } && "$@" > "$t" && mv "$t" "$f" || { rm -f "$t"; return 1; }
}
# The Claude keys of LEANKEYS that are absent from the settings file (a missing file reads as {}) and not in <added>,
# written; each one written is added to the caller's array w. A file that is not a JSON object is left as it is.
leanclaude() { # <added keys, JSON>
  local f k
  f=$(leanclaudef) || return 1
  if [ -e "$f" ] && ! leanjson "$f"; then echo "Claude settings not changed: $f is not valid JSON"; return 0; fi
  # A key is absent when its parent is absent, or an object without it; a parent of another type is the user's.
  k=$({ cat "$f" 2>/dev/null || echo '{}'; } | jq -c --argjson a "$1" --argjson l "$LEANKEYS" '. as $s | [$l[] | select(.key | IN($a[]) | not)
    | select(. as $k | (try ($s | getpath($k.path[:-1])) catch "x") as $o | $o == null or (($o | type) == "object" and ($o | has($k.path[-1]) | not)))]') || return 1
  [ "$k" != '[]' ] || return 0
  leanwritef "$f" jq --argjson l "$k" 'reduce $l[] as $k (.; setpath($k.path; $k.value))' <(cat "$f" 2>/dev/null || echo '{}') \
    || { echo "conveyor: the Claude settings $f could not be written" >&2; return 1; }
  mapfile -t -O "${#w[@]}" w < <(jq -r '.[].key' <<<"$k")
  echo "conveyor: wrote $(jq -r 'map(.key) | join(", ")' <<<"$k") in the Claude settings $f"
}
# Serena's web_dashboard line set to false, when the config is there, the line is true and <added> does not name it;
# LEANSERENA is then added to the caller's array w.
leanserena() { # <added keys, JSON>
  local f
  jq -e --arg k "$LEANSERENA" 'index($k) == null' <<<"$1" >/dev/null && f=$(leanserenaf) && [ -f "$f" ] || return 0
  grep -Eq "$(leandash true)" "$f" || return 0
  leanwritef "$f" sed -E "s/$(leandash true)/\\1false\\2/" "$f" \
    || { echo "conveyor: Serena's config $f could not be written" >&2; return 1; }
  w+=("$LEANSERENA"); echo "conveyor: turned off Serena's web dashboard in $f"
}
# Each key never written, written while the record's answer is yes; install() runs it after it installs a new commit.
# A machine with no yes takes no lock (the answer is read again under it).
leansettings() { [ "$(jq -r '.answer' "$(leanrec)" 2>/dev/null)" != yes ] || leanlocked leanwrite; }
leanwrite() {
  local a w=() rc=0
  [ "$(jq -r '.answer' "$(leanrec)" 2>/dev/null)" = yes ] || return 0
  a=$(leanadded); leanclaude "$a" || rc=1; leanserena "$a" || rc=1
  [ ${#w[@]} = 0 ] || leanput yes "$(jq -c '. + $ARGS.positional' --args "${w[@]}" <<<"$a")" || rc=1
  return $rc
}
# setup's step (`setup --lean-settings yes|no`): yes saves the answer and writes each key never written; no takes
# away each key of the record's added that still holds the value Conveyor wrote (the dashboard line set back to true
# while it is false), keeps every other, and saves the answer no. No answer changes nothing.
leanset() { # <yes|no|"">
  case $1 in yes) leanlocked leanyes ;; no) leanlocked leanno ;; *) return 0 ;; esac
}
leanyes() { leanput yes "$(leanadded)" && echo "conveyor: saved the answer yes to the lean settings in $(leanrec)" && leanwrite; }
leanno() {
  local a f k left
  a=$(leanadded); left=$a; f=$(leanclaudef) || return 1
  if [ -e "$f" ] && leanjson "$f"; then
    k=$(jq -c --argjson a "$a" --argjson l "$LEANKEYS" '. as $s | [$l[] | select(.key | IN($a[])) | select(. as $k | try ($s | getpath($k.path) == $k.value) catch false)]' "$f") || return 1
    [ "$k" = '[]' ] || { leanwritef "$f" jq --argjson l "$k" 'delpaths([$l[].path])' "$f" \
      && echo "conveyor: took away $(jq -r 'map(.key) | join(", ")' <<<"$k") from the Claude settings $f"; } \
      || { echo "conveyor: the Claude settings $f could not be written" >&2; return 1; }
    left=$(jq -c --argjson l "$LEANKEYS" 'map(select(IN($l[].key) | not))' <<<"$left")
  elif [ -e "$f" ]; then echo "Claude settings not changed: $f is not valid JSON"; fi
  if jq -e --arg k "$LEANSERENA" 'index($k) != null' <<<"$a" >/dev/null && f=$(leanserenaf) && [ -f "$f" ]; then
    ! grep -Eq "$(leandash false)" "$f" || { leanwritef "$f" sed -E "s/$(leandash false)/\\1true\\2/" "$f" \
      && echo "conveyor: turned Serena's web dashboard back on in $f"; } || { echo "conveyor: Serena's config $f could not be written" >&2; return 1; }
  fi
  left=$(jq -c --arg k "$LEANSERENA" 'map(select(. != $k))' <<<"$left")
  leanput no "$left" && echo "conveyor: saved the answer no to the lean settings in $(leanrec)"
}
# doctor's one line: the answer, each key of LEANKEYS as set (Conveyor's value, written by Conveyor), set by the user
# (there, not written by Conveyor or since changed) or missing, and Serena's web dashboard the same way.
leandoctor() {
  local a k f s=none
  a=$(jq -r '.answer | strings' "$(leanrec)" 2>/dev/null) && [ -n "$a" ] || a='not given'
  k=$(leanadded); f=$(leanclaudef)
  if [ -e "$f" ] && ! leanjson "$f"; then f="not read, $f is not valid JSON"
  else f=$({ cat "$f" 2>/dev/null || echo '{}'; } | jq -r --argjson a "$k" --argjson l "$LEANKEYS" '. as $s | [$l[] | . as $k
      | (try ($s | getpath($k.path)) catch null) as $v | "\($k.key) \(if $v == null then "missing" elif $v == $k.value and ($k.key | IN($a[])) then "set" else "set by the user" end)"] | join(", ")'); fi
  if [ -f "$(leanserenaf)" ]; then
    if ! grep -Eq '^web_dashboard:' "$(leanserenaf)"; then s='web_dashboard missing'
    elif grep -Eq "$(leandash false)" "$(leanserenaf)" && jq -e --arg k "$LEANSERENA" 'index($k) != null' <<<"$k" >/dev/null; then s='web_dashboard set'
    else s='web_dashboard set by the user'; fi
  fi
  echo "note: lean settings (setup --lean-settings): answer $a; $f; Serena config: $s"
}
