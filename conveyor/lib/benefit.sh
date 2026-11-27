# SPDX-License-Identifier: Apache-2.0
# The owner's yes on an issue's benefit (BENEFIT, lib/pick.sh), sourced by lib/issues.sh for openissues().
# The open issues given, each whose text has a line starting `Benefit approved:` with benefitYes: true when such a
# line was put in the text by the account gh is signed in as (GitHub's viewer: the account the Foreman adds the line
# with) or by the repository's owner (a user; an organization never edits). A collaborator can write or edit any
# issue's text, so who opened the issue or who last saved its text says nothing of who wrote the line: the line counts
# only when the version of the text that last brought it in (the one before lacks it; with no edit, the text as
# opened) was saved by one of those two. The yes is for the text they saw: one of them also saved the text as it is
# now, so a collaborator who rewrites the issue under the owner's line holds it again. The text, its edit history and the two accounts come from one GraphQL
# question asked after the list: the list's text only chooses which issues to ask about, so a line removed between
# the two reads gives no yes. History that cannot be read whole gives no yes: more than 100 versions, a version
# deleted from it, a newest version that is not the text, a first not saved by the author. The answer goes to jq as a
# file, not an argument: a long edit history is over the size of one argument.
benefityes() { # <open issues json>
  local qs='' n ns r
  ns=$(jq -r '.[] | select(any(.body // "" | splits("\r?\n"); startswith("Benefit approved:"))) | .number' <<<"$1") || return 1
  for n in $ns; do
    qs+=" i$n: issue(number: $n) { number body author { login } userContentEdits(first: 100) { totalCount nodes { editedAt deletedAt diff editor { login } } } }"
  done
  [ -n "$qs" ] || { printf '%s\n' "$1"; return 0; }
  # An issue deleted between the two reads makes gh fail with the others' answers: it gets no yes.
  r=$(gh api graphql -F owner='{owner}' -F repo='{repo}' -f query="query(\$owner: String!, \$repo: String!) { viewer { login }
    repository(owner: \$owner, name: \$repo) { owner { login }$qs } }") || jq -e '.data.viewer.login | strings' >/dev/null 2>&1 <<<"${r:-null}" \
    || { echo "conveyor: the benefit approvals of the open issues could not be read (gh api graphql)" >&2; return 1; }
  jq -c --slurpfile r <(printf '%s\n' "$r") '$r[0] as $r | def approvals: [splits("\r?\n") | select(startswith("Benefit approved:"))];
    def holds($a): any(approvals[]; . == $a);
    def versions: if .userContentEdits.totalCount == 0 then [{by: .author.login, text: .body}]
      else .userContentEdits.nodes | sort_by(.editedAt) | map({by: .editor.login, text: (if .deletedAt == null then .diff else null end)}) end;
    def yes($who): versions as $v | .body as $b
      | .userContentEdits.totalCount == (.userContentEdits.nodes // [] | length) and all($v[]; .text | type == "string")
      and $v[-1].text == $b and $v[0].by == .author.login and ($v[-1].by | IN($who[]))
      and any($b | approvals[]; . as $a | [range($v | length) | select(. as $k | ($v[$k].text | holds($a)) and ($k == 0 or ($v[$k - 1].text | holds($a) | not)))]
        | last as $k | $v[$k].by | IN($who[]));
    [$r.data.viewer.login, $r.data.repository.owner.login | strings] as $who | [$r.data.repository // {} | .[] | objects | select(.number != null)] as $got
    | map(.number as $n | (first($got[] | select(.number == $n)) // null) as $i | if $i == null then . else .benefitYes = ($i | yes($who)) end)' <<<"$1"
}
