# SPDX-License-Identifier: Apache-2.0
# The area of a file, from the pack's path-to-area map (labels.areaPaths): the area of an entry of the self-heals list
# or the docs list (areapick(), healsadd(), lib/followups.sh), the area label of what the engine files (filearea():
# follow-ups, an entry moved up to harm, flaky tests, main red, the whole test on main, release fixes, batch cards,
# split parts, declined findings, test rules, test-speed surveys, File on GitHub, the Foreman's card and testissue), and
# the one pass that gives what exists an area (healsareas()). The map is the pack's: the plugin names no path and no
# area. A pack with no map gives no area here: an entry keeps its issue's area label, and a filing has only a label
# it takes from what it was made of (a follow-up or a split part its parent's, an entry moved up to harm its parent's
# or its own, File on GitHub its card's, a flaky issue <areaPrefix>engine when nonProductAreas names it). Sourced by
# lib/prompts.sh, which reads the map (names(): AREAPATHS).

# The jq of the map, $m (labels.areaPaths: {paths: {<path>: <area label>}, other: <area label>}, or null for none):
#   areaof($m): the area label of the path on the input: that of the longest line of paths that names it (a line
#     ending in / names each file under that folder, any other line one file), else other; null for no path or no map.
#   fileof($m; $c): the first file the text on the input names, as a path from the repository root: its first file:line
#     (as a review finding cites one), else its first path in backticks with a / in it, else its first path written
#     plain with a / in it and a file's extension (hooks/sources.ts, as a split's Done-when names one; not part of a
#     URL), else its first file at the root, plain or in backticks, that is a line of the map's paths (README.md; a
#     setting such as labels.areaPaths is no line, so it is none), else the text itself when it is one path. A path
#     has a / in it or ends in a file's extension (.<letter>...): a clock time (00:05) or a test case's name (apicodex)
#     is none. A path under the card worktrees' folder $c (CARDS) is read as one in its card's worktree; another
#     absolute path, or one with a . or .. part, is none. null when the text names none.
#   areatext($m; $c): the area of the file the text names; null when it names none.
#   filingarea($m; $c): the same, else the map's other: a filing always has an area when the pack has a map.
AREAJQ='def areaof($m): . as $p | if ($m | type) != "object" or ($p | type) != "string" or $p == "" then null
    else ([$m.paths // {} | to_entries[] | .key as $k | select($p == $k or (($k | endswith("/")) and ($p | startswith($k))))] | max_by(.key | length) | .value) // $m.other end;
  def repopath($c): ltrimstr("./")
    | if startswith("/") then (if $c != "" and startswith($c + "/") then ltrimstr($c + "/") | sub("^[^/]+/"; "") else empty end) else . end
    | select(. != "" and (("/" + . + "/") | test("/\\.\\.?/") | not) and test("/|\\.[A-Za-z][A-Za-z0-9]*$"));
  def fileof($m; $c): first(((scan("([A-Za-z0-9_./-]+):[0-9]{1,9}") | .[0]), (scan("`([A-Za-z0-9_./-]*/[A-Za-z0-9_./-]*)`") | .[0]),
      (scan("(?<![A-Za-z0-9_./:-])([A-Za-z0-9_.-]+/[A-Za-z0-9_./-]*\\.[A-Za-z][A-Za-z0-9]*)(?![A-Za-z0-9_/-])") | .[0]),
      (scan("(?<![A-Za-z0-9_./:-])([A-Za-z0-9_-][A-Za-z0-9_.-]*\\.[A-Za-z][A-Za-z0-9]*)(?![A-Za-z0-9_/-])") | .[0]
        | select(. as $f | $m | objects | .paths | objects | has($f))), (select(test("^[A-Za-z0-9_./-]+$")))) | repopath($c)) // null;
  def areatext($m; $c): fileof($m; $c) | areaof($m);
  def filingarea($m; $c): areatext($m; $c) // ($m | objects | .other);'
# The pack's map as JSON, null when it has none. names() (lib/prompts.sh) reads it at every turn; a shell that has not
# run names() reads it here.
areamap() {
  [ -v AREAPATHS ] || { packget labels.areaPaths AREAPATHS 2> /dev/null || AREAPATHS=''; }
  printf '%s\n' "${AREAPATHS:-null}"
}
# The area label of the file <text> names (fileof above; with filing, the map's other when it names none). Prints
# nothing when the pack has no map, or for an entry's text that names no file. Fails when the map cannot be read.
areafor() { # <text> [filing]
  local m
  m=$(areamap) || return 1
  [ "$m" != null ] || return 0
  jq -rn --arg t "$1" --arg c "${CARDS:-}" --argjson m "$m" --arg f "${2:-}" "$AREAJQ"'$t | if $f == "" then areatext($m; $c) else filingarea($m; $c) end // empty'
}
# The area of a list entry (healsadd(), lib/followups.sh): that of the file its finding names, else <area label> (its
# issue's, or none). The issue's label is used only when the finding names no file.
areapick() { # <finding> <area label | "">
  local a
  a=$(areafor "$1") || a=''
  printf '%s\n' "${a:-$2}"
}
# The area label of a filing: <area label> when given (a follow-up's or a split part's parent's), else that of the
# file <text> names (its test file, its finding, its scope), else the map's other. Nothing with no map and no label.
filearea() { # <area label | ""> <text>
  [ -z "$1" ] || { printf '%s\n' "$1"; return 0; }
  areafor "$2" filing
}
# The area label of a card ordered by its title and body (cardnew(), lib/testaction.sh): that of the file <body> names,
# else of the first word of <title> that is a path (`Fix a.test.sh`), else the map's other. Nothing with no map.
cardarea() { # <title> <body>
  local a w ws
  a=$(areafor "$2") || return 1
  read -ra ws <<<"$1"
  for w in "${ws[@]}"; do
    [ -z "$a" ] || break
    w=${w//\`/}; a=$(areafor "${w%%[.,:;!?)]}") || return 1
  done
  printf '%s\n' "${a:-$(areafor "" filing)}"
}
# The doctor's line on the map (doctor(), lib/setup.sh): a warning when the pack <pack> sets none.
areadoctor() { # <pack>
  [ "$(jq -c '.labels.areaPaths // null' "$1" 2> /dev/null)" = null ] || return 0
  echo "warning: the pack sets no labels.areaPaths, so an entry of the self-heals list or the docs list takes its area from its issue's area label alone, and the engine files an issue or a card with no area label of its own (a follow-up or a split part has its parent's, a flaky issue <areaPrefix>engine when nonProductAreas names it); fix: add the map to the pack's labels (docs/configuration.md, The pack), then run conveyor.sh heals areas"
}
# `conveyor.sh heals areas`: the one pass over what exists, once the pack has a map. Each entry of the self-heals list
# and the docs list with no area gets the area of the file its finding names (one that names no file keeps none, and
# the Board shows it under No area); an entry that has an area keeps it. Each list changes under its lock, as healsadd()
# writes it. Then each label of the map that the repository lacks is made on GitHub, as setup makes the pack's labels
# (lib/setup.sh), and each open issue with no area label gets the area of the file its body names, else the map's
# other. Prints what it changed; fails when a list could not be written, the labels could not be read or one could not
# be made (then no issue is labelled), or an issue could not be read or labelled. With no map it changes nothing (exit 2).
healsareas() {
  local m f k n iss l have rc=0 done=0
  m=$(areamap) && [ "$m" != null ] || { echo "conveyor: the pack sets no labels.areaPaths, so nothing gets an area; add the map first" >&2; return 2; }
  for f in "$SELFHEALS" "$DOCSDRIFT"; do
    [ -s "$f" ] || continue
    k=$( (flock 9 || exit 1
      jq -c --argjson m "$m" --arg c "${CARDS:-}" "$AREAJQ"'if type == "object" and (.area // "") == "" then (.finding // "" | areatext($m; $c)) as $a
        | if $a == null then . else .area = $a end else . end' "$f" > "$f.new" || { rm -f "$f.new"; exit 1; }
      n=$(jq -s --slurpfile o "$f" '[to_entries[] | select(.value != $o[.key])] | length' "$f.new") && mv -f "$f.new" "$f" || { rm -f "$f.new"; exit 1; }
      printf '%s\n' "$n" ) 9>> "$f.lock") || { echo "conveyor: $f could not be given its areas" >&2; return 1; }
    echo "conveyor: $k entries of $f given the area of their finding's file"
  done
  have=$(timeout 60 gh label list --limit 10000 --json name --jq '.[].name') || { echo "conveyor: the repo's labels could not be read; no issue labelled" >&2; return 1; }
  while IFS= read -r l; do
    grep -qixF -- "$l" <<<"$have" || gh_write label create -- "$l" > /dev/null || { echo "conveyor: the label $l could not be made; no issue labelled" >&2; return 1; }
  done < <(jq -r '[(.paths // {})[], .other] | unique[]' <<<"$m")
  iss=$(openissues number,labels,body) || { echo "conveyor: the open issues could not be read; none labelled" >&2; return 1; }
  while IFS=$'\t' read -r n l; do
    if gh_write issue edit "$n" --add-label "$l" > /dev/null 2>&1; then done=$((done + 1)); else echo "conveyor: #$n could not be given the label $l" >&2; rc=1; fi
  done < <(jq -r --arg p "$AREA" --argjson m "$m" --arg c "${CARDS:-}" "$AREAJQ"'.[] | select(any(.labels[]?; .name | startswith($p)) | not)
    | [.number, (.body // "" | filingarea($m; $c))] | @tsv' <<<"$iss")
  echo "conveyor: $done open issues given an area label"
  return $rc
}
