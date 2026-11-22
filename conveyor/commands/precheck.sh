# SPDX-License-Identifier: Apache-2.0
# `conveyor.sh precheck [<issue> <reply file>]`: what the engine checks after a build or fix session, run in the card's
# worktree (CALLED) before the session ends, so a failure is mended in the session and not in a fix session of its own:
# the project's checks (test.checkCommand, run as treecheck() runs it, but its result is not kept: a session may write
# only in its worktree and the temporary folders, and the engine runs them again after the session), the commit trailers
# the pack requires of the files the change adds (owing()), and, given the issue number and a file with the reply so far
# (a relative path is read from the folder it was called in), the form of its `## Done when` section and the markers it
# must name (dwform()). It prints each failure and exits 1; with none it prints `precheck: passed` and exits 0. It stages
# nothing: the trailers and the markers are read from a copy of the index, in which the reply file is not part of the
# change, and the new files' objects go to a temporary folder (a session may not write in the repository's own object
# folder). It makes no state folder. Sourced by conveyor.sh.
. "$HERE/lib/slots.sh" || exit 1
. "$HERE/lib/prompts.sh" || exit 1
. "$HERE/lib/lint.sh" || exit 1
. "$HERE/lib/donewhen.sh" || exit 1
# Removes the copy of the index and the temporary object folder.
pcclean() { rm -rf "$PCIDX" "$PCOBJ"; }
[ $# = 1 ] || [ $# = 3 ] || { echo "usage: conveyor.sh precheck [<issue> <reply file>]" >&2; exit 2; }
PCTOP=$(git -C "$CALLED" rev-parse --show-toplevel 2>/dev/null) || { echo "conveyor precheck: $CALLED is in no git checkout" >&2; exit 2; }
PCBAD=0
packget test.checkCommand pccc || { echo "conveyor precheck: the project pack's test.checkCommand could not be read" >&2; exit 2; }
if [ -n "$pccc" ]; then
  pcout=$(cd "$PCTOP" && bash -c "$pccc" 2>&1 < /dev/null 8>&-) || { PCBAD=1; printf 'The checks failed (test.checkCommand: %s):\n%s\n' "$pccc" "${pcout:0:20000}"; }
fi
PCIDX=$(mktemp) && PCOBJ=$(mktemp -d) && PCALT=$(git -C "$PCTOP" rev-parse --path-format=absolute --git-path objects) \
  || { pcclean; echo "conveyor precheck: a temporary file could not be made" >&2; exit 2; }
# New objects go to PCOBJ; the repository's own are read through it.
export GIT_OBJECT_DIRECTORY=$PCOBJ GIT_ALTERNATE_OBJECT_DIRECTORIES=$PCALT
lintindex "$PCTOP" "$PCIDX" || { pcclean; echo "conveyor precheck: the worktree's files could not be read" >&2; exit 2; }
if [ $# = 3 ]; then
  pcreply=$3; [[ $pcreply == /* ]] || pcreply=$CALLED/$pcreply
  pcissue=$(gh issue view "$2" --json number,title,body,labels,milestone) && [ -r "$pcreply" ] || { pcclean; echo "conveyor precheck: the issue $2 or the reply file $3 could not be read" >&2; exit 2; }
  # The draft reply is not part of the change: out of the index copy when it lies in the worktree and git does not track it.
  pcfull=$(cd "$(dirname "$pcreply")" && pwd -P)/${pcreply##*/}
  if [[ $pcfull == "$PCTOP"/* ]] && ! git -C "$PCTOP" ls-files --error-unmatch -- ":(literal)${pcfull#"$PCTOP"/}" > /dev/null 2>&1; then
    GIT_INDEX_FILE=$PCIDX git -C "$PCTOP" rm -q --cached --ignore-unmatch -- ":(literal)${pcfull#"$PCTOP"/}" > /dev/null \
      || { pcclean; echo "conveyor precheck: the reply file could not be left out of the change" >&2; exit 2; }
  fi
fi
pcowe=$(GIT_INDEX_FILE=$PCIDX owing "$PCTOP"); pcr=$?
[ $pcr = 0 ] || { pcclean; echo "conveyor precheck: the commit trailers that the pack requires could not be read" >&2; exit 2; }
if [ -n "$pcowe" ]; then
  PCBAD=1
  jq -r '"A commit trailer is missing: \(.token) (the change adds \(.paths | join(", "))). \(.ask)"' <<<"$pcowe"
  echo "Write each in $PCTOP.trailers, one line \`<Token>: <text>\`."
fi
if [ $# = 3 ]; then
  pcform=$(GIT_INDEX_FILE=$PCIDX dwform "$PCTOP" "$pcissue" "$pcreply") || { pcclean; echo "conveyor precheck: the Done-when form could not be checked" >&2; exit 2; }
  [ -z "$pcform" ] || { PCBAD=1; printf 'The Done-when section of the reply does not hold:\n%s\n' "$pcform"; }
fi
pcclean
[ $PCBAD = 0 ] || exit 1
echo "precheck: passed"
