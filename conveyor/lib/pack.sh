#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# The project pack reader (plan docs/plans/conveyor-plugin-2026-11-10.md, sections 5 and 6).
# Usage: pack.sh check [<pack>] | get <field> [<pack>]
#   check: exit 0 when the pack matches conveyor/schema/pack.schema.json; otherwise each mismatch on stderr, exit 1.
#   get:   checks the pack, then prints one field (dotted path, such as labels.built or tunables.poll): a string as it
#          is, anything else as compact JSON; a field left out prints the schema's default, or nothing when it has none.
#          A field the schema does not name is an error (exit 2).
# <pack> defaults to .conveyor/project.json at the top of the git checkout holding the current directory.
# The schema is checked with jq, not a JSON Schema library (the engine is bash + jq, plan section 4), so the schema
# may use only the keywords in KNOWN below: a schema using another fails every check rather than going unchecked.
# Sourced (by lib/prompts.sh), it only defines SCHEMA, CHECK, GET and packcheck, for a check of the pack's text as read.
set -uo pipefail
# This file's folder by bash's own text handling, not a dirname program (a path with no slash is in the current folder).
PACKLIB=.; [[ ${BASH_SOURCE[0]} != */* ]] || PACKLIB=${BASH_SOURCE[0]%/*}
SCHEMA=$(cd "$PACKLIB/../schema" && pwd -P)/pack.schema.json; unset PACKLIB

CHECK='
def KNOWN: ["$schema", "$id", "$comment", "title", "description", "default", "type", "required", "properties",
  "additionalProperties", "items", "enum", "minimum", "minLength", "minItems"];
# A field the pack held once, and where its setting lives now.
def MOVED: {".judge": "the pack holds the review judge no more: it is set in the control record, with conveyor.sh control judge <on|off> and conveyor.sh control judge always [<kind>...], or on the Board"};
def is($t): $t == type or ($t == "integer" and type == "number" and . == floor);
# Every subschema is walked, not only those of fields the pack has, so an optional field cannot hide a keyword.
def unknown($p):
  (keys - KNOWN | select(. != []) | "\($p): the schema uses \(join(", ")), which pack.sh does not check"),
  (.properties // {} | to_entries[] | .key as $k | .value | unknown("\($p).\($k)")),
  (.items | select(type == "object") | unknown("\($p)[]")),
  (.additionalProperties | select(type == "object") | unknown("\($p).*"));
def errs($s; $p):
  . as $v
  | if $s.type != null and ([$s.type] | flatten | any(. as $t | $v | is($t)) | not) then
      "\($p): \(type), not \([$s.type] | flatten | join(" or "))"
    else
      (if $s.enum != null and ($s.enum | any(.[]; . == $v) | not) then "\($p): \($v | tojson) is not one of \($s.enum | tojson)" else empty end),
      (if $s.minimum != null and type == "number" and . < $s.minimum then "\($p): \(.) is below \($s.minimum)" else empty end),
      (if $s.minLength != null and type == "string" and length < $s.minLength then "\($p): shorter than \($s.minLength)" else empty end),
      (if $s.minItems != null and type == "array" and length < $s.minItems then "\($p): fewer than \($s.minItems) items" else empty end),
      (if type == "array" and $s.items != null then to_entries[] | .key as $i | .value | errs($s.items; "\($p)[\($i)]") else empty end),
      (if type == "object" then
         ($s.required // [] | .[] | select(. as $k | $v | has($k) | not) | "\($p).\(.): missing (required)"),
         (to_entries[] | .key as $k | .value
           | if $s.properties[$k] != null then errs($s.properties[$k]; "\($p).\($k)")
             elif $s.additionalProperties == false then "\($p).\($k): \(MOVED["\($p).\($k)"] // "not a field of the schema")"
             elif ($s.additionalProperties | type) == "object" then errs($s.additionalProperties; "\($p).\($k)")
             else empty end)
       else empty end)
    end;
# The plugin is one pinned commit or what it follows (releases or main): a pack naming both, or neither, says which to set.
def plugin: objects | .plugin | objects | select(has("commit") == has("follow"))
  | ".plugin: \(if has("commit") then "both commit and follow are set" else "neither commit nor follow is set" end): set one, commit (a full commit id: the project runs that commit) or follow: \"releases\" (the project runs the plugin'"'"'s newest release) or \"main\" (the plugin'"'"'s main as it moves)";
[$schema[0] | unknown("")] as $bad
| if $bad != [] then $bad[] elif length != 1 then "\(length) JSON documents, not one" else .[0] | errs($schema[0]; ""), plugin end'

# get's field ($f) of the pack ($v) by the schema ($s): the field's schema, walked by its keys, and none means the
# schema does not name it (exit 2).
GET='($f | split(".")) as $p
| (reduce $p[] as $k ($s; if . == null then null else .properties[$k] // (.additionalProperties | if type == "object" then . else null end) end)) as $fs
| if $fs == null then "conveyor pack: \($f): not a field of the schema\n" | halt_error(2) end
| $v | getpath($p) | if . == null then (if $fs | has("default") then $fs.default else empty end) end | if type == "string" then . else tojson end'

# The check of the pack file, or, given them, of its text and the schema's text (the file is named in each message).
packcheck() { # <pack> [<its text> <the schema's text>]
  local out l
  if [ $# = 1 ]; then
    [ -f "$1" ] || { echo "conveyor pack: $1: no such file" >&2; return 1; }
    out=$(jq -rs --slurpfile schema "$SCHEMA" "$CHECK" "$1" 2>&1)
  else
    out=$(jq -rs --slurpfile schema <(printf '%s' "$3") "$CHECK" <<<"$2" 2>&1)
  fi || { echo "conveyor pack: $1: not readable JSON: $out" >&2; return 1; }
  [ -z "$out" ] || { while IFS= read -r l; do echo "conveyor pack: $1: $l"; done <<<"$out" >&2; return 1; }
}
[ "${BASH_SOURCE[0]}" = "$0" ] || return 0

usage() { echo "usage: pack.sh check [<pack>] | get <field> [<pack>]" >&2; exit 2; }

cmd=${1:-}; [ $# -gt 0 ] && shift
case $cmd in
  check) [ $# -le 1 ] || usage ;;
  get) [ $# -ge 1 ] && [ $# -le 2 ] || usage; field=$1; shift ;;
  *) usage ;;
esac
pack=${1:-$(git rev-parse --show-toplevel 2>/dev/null)/.conveyor/project.json}
packcheck "$pack" || exit 1
[ "$cmd" = get ] || exit 0
jq -r --arg f "$field" --slurpfile s "$SCHEMA" '. as $v | $s[0] as $s | '"$GET" "$pack"
