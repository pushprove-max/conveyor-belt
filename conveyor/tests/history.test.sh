#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases: the history scan and rewrite run before a repository is made public (tools/history-scan.sh,
# tools/history-rewrite.sh).
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# histrepo <folder>: a fixture repository, a gh stub on PATH that answers the issue lists from <folder>/gh.<list>.json
# (an empty list when there is none) and a terms file of one term, Zed, in <folder>/terms.
histrepo() {
  local d=$1; mkdir -p "$d/bin"; git init -q -b main "$d/repo" || fail "no fixture repository"
  printf '#!/usr/bin/env bash\ncase "$*" in *pulls/comments*) f=pulls ;; *issues/comments*) f=comments ;; *) f=issues ;; esac\ncat "%s/gh.$f.json" 2>/dev/null || echo "[]"\n' "$d" > "$d/bin/gh"
  chmod +x "$d/bin/gh"; PATH=$d/bin:$PATH; printf '# a comment line\nZed\n' > "$d/terms"
}
commit() { # <repo> <message> <date>: commits every change, authored and committed at <date>
  git -C "$1" add -A && GIT_AUTHOR_DATE=$3 GIT_COMMITTER_DATE=$3 git -C "$1" commit -qm "$2" || fail "the fixture commit failed"
}

# Bug caught: a secret or a private term that a later commit removed is still in the history and goes public with
# it; a scan of the tree as it is now, or of new changes only, misses it. Old commits add a token (put together here, so
# this file holds none itself), a term in a file, a term in a message and a term in an issue's comment; the last
# commit removes the first two. The scan names each hit's commit and path (and line), never the text.
# Also caught: the repository's own text hides a hit from gitleaks: both lines carry gitleaks' "gitleaks:allow" marker
# (in a file of a binary type, by the commits' .gitattributes), and the checkout holds a .gitleaksignore naming the
# token's hit and a .gitleaks.toml whose allowlist covers every path.
t_histscan() {
  local d=$T/$CASE out rc c1 c2; histrepo "$d"
  echo '*.md binary' > "$d/repo/.gitattributes"
  printf 'token = %s_%s # gitleaks:allow\n' ghp aB3dE5fG7hJ9kL1mN3pQ5rS7tU9vW1xY3zA5 > "$d/repo/conf.txt"; commit "$d/repo" one 2026-01-01T00:00:00Z
  printf 'line\nsee zed for this #gitleaks:allow\n' > "$d/repo/notes.md"; commit "$d/repo" $'two\n\nfrom ZED' 2026-01-02T00:00:00Z
  c1=$(git -C "$d/repo" rev-parse HEAD~1); c2=$(git -C "$d/repo" rev-parse HEAD)
  echo clean > "$d/repo/conf.txt"; echo clean > "$d/repo/notes.md"; commit "$d/repo" three 2026-01-03T00:00:00Z
  echo "$c1:conf.txt:github-pat:1" > "$d/repo/.gitleaksignore"
  printf '[extend]\nuseDefault = true\n[allowlist]\npaths = ['"'''.*'''"']\n' > "$d/repo/.gitleaks.toml"
  echo '[{"issue_url": "https://api.github.invalid/repos/o/r/issues/12", "body": "a word on Zed"}]' > "$d/gh.comments.json"
  out=$("$SRC/tools/history-scan.sh" --terms "$d/terms" "$d/repo" 2>&1); rc=$?
  [ $rc = 1 ] || fail "the scan exited $rc, not 1, on a history with hits: $out"
  grep -qx "$c1 conf.txt:1: github-pat" <<<"$out" || fail "the old commit's token is not listed with its commit and path: $out"
  grep -qx "$c2 notes.md:2: private term (terms file line 2)" <<<"$out" || fail "the old commit's term is not listed with its commit and path: $out"
  grep -qx "$c2 (message):3: private term (terms file line 2)" <<<"$out" || fail "the term in a commit message is not listed: $out"
  grep -qx "issue #12: private term (terms file line 2)" <<<"$out" || fail "the issue whose comment holds the term is not listed: $out"
  [ "$(wc -l <<<"$out")" = 4 ] || fail "the scan lists hits beyond the four: $out"
  ! grep -qi 'zed\|ghp_' <<<"$out" || fail "the scan prints the matched text: $out"
}

# Bug caught: a clean history reported as holding hits (or a failure), so the owner cannot tell it is ready to go
# public; and a term that is part of a longer word reported, as the check matches whole words.
t_histclean() {
  local d=$T/$CASE out rc; histrepo "$d"
  printf 'nothing here but zedlike words\n' > "$d/repo/a.txt"; commit "$d/repo" one 2026-01-01T00:00:00Z
  out=$("$SRC/tools/history-scan.sh" --terms "$d/terms" "$d/repo" 2>&1); rc=$?
  [ $rc = 0 ] && [ -z "$out" ] || fail "the scan of a clean history exited $rc and printed: $out"
  # An issue list that cannot be read is not a clean one.
  printf '#!/usr/bin/env bash\necho "HTTP 404" >&2; exit 1\n' > "$d/bin/gh"
  out=$("$SRC/tools/history-scan.sh" --terms "$d/terms" "$d/repo" 2>&1); rc=$?
  [ $rc = 2 ] && grep -q 'the issues cannot be read' <<<"$out" || fail "a failed issue list passed as clean (exit $rc): $out"
}

# Bug caught: a secret or a private term added while a merge is made (in its resolution, in no parent) goes public
# unread, as git log -p shows no diff for a merge commit. Here a merge adds both to a file neither parent changed.
t_histmerge() {
  local d=$T/$CASE out rc m; histrepo "$d"
  echo base > "$d/repo/a.txt"; echo base > "$d/repo/b.txt"; commit "$d/repo" base 2026-01-01T00:00:00Z
  git -C "$d/repo" checkout -qb side; echo side > "$d/repo/b.txt"; commit "$d/repo" side 2026-01-02T00:00:00Z
  git -C "$d/repo" checkout -q main; echo main > "$d/repo/c.txt"; commit "$d/repo" main 2026-01-03T00:00:00Z
  git -C "$d/repo" merge -q --no-ff --no-commit side >/dev/null 2>&1 || fail "the fixture merge failed"
  printf 'token = %s_%s\nZed\n' ghp aB3dE5fG7hJ9kL1mN3pQ5rS7tU9vW1xY3zA5 > "$d/repo/a.txt"; commit "$d/repo" merge 2026-01-04T00:00:00Z
  m=$(git -C "$d/repo" rev-parse HEAD); [ -n "$(git -C "$d/repo" rev-parse -q --verify HEAD^2)" ] || fail "the fixture made no merge"
  out=$("$SRC/tools/history-scan.sh" --terms "$d/terms" "$d/repo" 2>&1); rc=$?
  [ $rc = 1 ] || fail "the scan exited $rc, not 1, on a merge that adds a secret: $out"
  grep -qx "$m a.txt:1: github-pat" <<<"$out" || fail "the token the merge adds is not listed: $out"
  grep -qx "$m a.txt:2: private term (terms file line 2)" <<<"$out" || fail "the term the merge adds is not listed: $out"
}

# Bug caught: the rewrite leaves the name in an old commit, or in a message, or changes who wrote a commit or when,
# or changes the source repository. Two commits on two branches name the repository; afterwards no commit of the
# result holds it, each commit's authors and dates are the same, and the source's refs and content are as before.
t_histrewrite() {
  local d=$T/$CASE out rc before after commits; histrepo "$d"
  printf 'cloned from github.com/o/Secret-Proj\n' > "$d/repo/a.txt"; commit "$d/repo" 'one: for secret-proj' 2026-01-01T00:00:00Z
  git -C "$d/repo" checkout -qb side; printf 'secret-project is another word\n' > "$d/repo/b.txt"
  GIT_AUTHOR_NAME=u GIT_AUTHOR_EMAIL=u${AT}example.com commit "$d/repo" two 2026-01-02T00:00:00Z
  echo 'Secret-Proj again' >> "$d/repo/a.txt"; commit "$d/repo" three 2026-01-03T00:00:00Z
  before=$(git -C "$d/repo" for-each-ref --format='%(refname) %(objectname)')
  out=$("$SRC/tools/history-rewrite.sh" "$d/repo" "$d/new" secret-proj 2>&1); rc=$?
  [ $rc = 0 ] || fail "the rewrite exited $rc: $out"
  [ "$(git -C "$d/repo" for-each-ref --format='%(refname) %(objectname)')" = "$before" ] && [ -z "$(git -C "$d/repo" status --porcelain)" ] \
    && grep -q Secret-Proj "$d/repo/a.txt" || fail "the source repository changed"
  [ -z "$(git -C "$d/new" remote)" ] || fail "the result keeps a remote a push could reach"
  [ "$(git -C "$d/new" rev-list --all | wc -l)" = 3 ] || fail "the result does not hold the three commits"
  mapfile -t commits < <(git -C "$d/new" rev-list --all)
  ! git -C "$d/new" grep -qiw secret-proj "${commits[@]}" &&! git -C "$d/new" log --all --format=%B | grep -qiw secret-proj \
    || fail "a commit of the result still names the repository"
  git -C "$d/new" grep -q 'secret-project is another word' side || fail "a longer word holding the name was changed"
  [ "$(git -C "$d/new" show main:a.txt)" = 'cloned from github.com/o/example-project' ] \
    && [ "$(git -C "$d/new" log -1 --format=%B main | head -1)" = 'one: for example-project' ] || fail "the name is not replaced with example-project"
  after=$(git -C "$d/new" log --all --date-order --format='%an %ae %aI %cn %ce %cI')
  [ "$after" = "$(git -C "$d/repo" log --all --date-order --format='%an %ae %aI %cn %ce %cI')" ] || fail "authors or dates changed: $after"
  # The map pairs each source commit with its new one.
  [ "$(wc -l <<<"$out")" = 3 ] && grep -qx "$(git -C "$d/repo" rev-parse side) $(git -C "$d/new" rev-parse side)" <<<"$out" \
    || fail "the report gives no old-to-new commit map: $out"
}
