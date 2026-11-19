#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases: `conveyor.sh release-prep <version>` and `conveyor.sh release <version>`, a release made on the build
# machine (docs/releases.md, Making a release).
# Each case makes one fixture and runs the commands on it one after another, as an owner would: a case costs its
# fixture and the runner's start and end of it, which were most of this file's CPU when each run had a case of its own.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# relsetup <full-cmd> [nonotes|<notes text>] [notag]: main's pack names a whole suite (test.full: $STUB/full-cmd, which
# notes the commit it ran on); origin has the release v1.0.0 (its commit names issue #1 and adds a README with the
# sections Cards and The Board; with notag, that commit is not tagged) and two commits after it, the first
# naming issue #5 in its subject, the second issue #7 in a Closes line and adding docs/releases/1.1.0.md (not with
# nonotes; with <notes text>, that text); main has one more commit origin lacks. gh records each call, and `gh issue
# view <n>` prints issue n of the fixture issues (#1, #5, #7). A case that drafts notes writes the model, the stub
# claude. O is origin's head, the commit release-prep must test and post on.
relsetup() {
  setup '[{"number":1,"title":"Old","body":"BEFORE-BODY"},{"number":5,"title":"Hold a card","body":"HOLD-BODY"},{"number":7,"title":"Faster board","body":"FAST-BODY"}]'
  tune '.test.full = ". \"$STUB/full-cmd\""'
  printf 'git rev-parse HEAD > "$STUB/full-at"\n%s\n' "$1" > "$STUB/full-cmd"
  printf '%s\n' '#!/usr/bin/env bash' 'printf "%s\n" "$*" >> "$STUB/gh-calls"' \
    '[ "$1 $2" != "issue view" ] || jq -c --argjson n "$3" ".[] | select(.number == \$n)" "$STUB/issues.json"' > "$STUB/gh"
  printf '# Fixture\n\nREADME-INTRO\n\n## Cards\n\n- A card waits.\n\n## The Board\n\n- A page.\n' > "$R/README.md" && git -C "$R" add README.md \
    && git -C "$R" commit -q -m 'fix: before the release (#1)' && { [ "${3:-}" = notag ] || git -C "$R" tag v1.0.0; } \
    && git -C "$R" commit -q --allow-empty -m 'feat(engine): A new thing (#5)' || fail "the fixture could not be made"
  [ "${2:-}" = nonotes ] || { mkdir -p "$R/docs/releases" && printf '%s\n' "${2:-- A fix}" > "$R/docs/releases/1.1.0.md" && git -C "$R" add docs; } || fail "the fixture could not be made"
  git -C "$R" commit -q --allow-empty -m 'fix: A fix' -m 'Closes #7'
  git -C "$R" push -q origin main && { [ "${3:-}" = notag ] || { git -C "$R" push -q origin v1.0.0 && git -C "$R" tag -d v1.0.0 > /dev/null; }; } \
    || fail "the fixture could not be made"
  git -C "$R" commit -q --allow-empty -m 'feat: Not pushed yet'
  O=$(git -C "$T/$CASE/origin" rev-parse refs/heads/main)
}

# relmodel <answer>: the model (the stub claude) keeps its prompt in $STUB/notes-prompt and answers <answer>.
relmodel() { printf '#!/usr/bin/env bash\ncat > "$STUB/notes-prompt"\nprintf "%%s\\n" %q\n' "$1" > "$STUB/claude"; }

# release-prep on a head with no notes: the project's first release, then, v1.0.0 tagged, its next.
# Bugs: a project's first release (no tag) is drafted from every commit ever made, an engineering log, rather than as an
# overview of what the project does, in sections from its README (the model there copies its whole prompt into the
# draft, so a commit subject or an issue given to it would show in the draft). Then: the suite ran and its status was
# posted on a head without the notes (committing the notes then makes a new head, and `release`, which checks the
# status of the head it releases, runs the suite again); the notes draft is not the model's, or the model is not given
# the issues landed since the last release (named by "(#N)" or by a Closes line), their bodies, the commit subjects
# and the style, or is given an issue from before it; a draft that breaks the style is shown as if it were ready to
# commit; a model that gives no notes leaves an empty draft, or an earlier run's, to be taken for this run's.
t_reldraft() {
  local O out s
  relsetup true nonotes notag; printf '#!/usr/bin/env bash\ntee "$STUB/notes-prompt"\n' > "$STUB/claude"
  out=$(loop release-prep 1.0.0 2>&1); [ $? = 1 ] && grep -qF "the notes draft, an overview from the README and docs, as no release is tagged yet, is $ST/release/1.0.0.md. " <<<"$out" \
    || fail "release-prep did not draft an overview for a project with no release: $out"
  [ "$(grep '^## ' "$ST/release/1.0.0.md")" = $'## Cards\n## The Board' ] && grep -q README-INTRO "$ST/release/1.0.0.md" \
    && grep -q '^- Begin with the line "# 1.0.0"' "$ST/release/1.0.0.md" || fail "the draft's sections are not the README's: $(cat "$ST/release/1.0.0.md" 2>&1)"
  while IFS= read -r s; do
    ! grep -qF "${s% (#*}" "$ST/release/1.0.0.md" || fail "the draft takes a line from the commit subject '$s': $(cat "$ST/release/1.0.0.md")"
  done < <(git -C "$R" log --format=%s "$O")
  ! grep -qE 'BODY|^issue ' "$ST/release/1.0.0.md" "$STUB/gh-calls" 2>/dev/null || fail "issues were read for a first release: $(cat "$STUB/gh-calls" 2>&1)"

  # v1.0.0 on origin, on the commit relsetup tags without notag.
  git -C "$R" push -q origin HEAD~3:refs/tags/v1.0.0 || fail "the fixture could not be made"
  relmodel $'# 1.1.0\n\nCards can wait.\n\n## Cards\n\n- You can hold a card.'
  out=$(loop release-prep 1.1.0 2>&1); [ $? = 1 ] || fail "release-prep did not stop on a head with no notes: $out"
  [ ! -e "$STUB/full-at" ] || fail "the suite ran on a head with no notes"
  ! grep -q statuses "$STUB/gh-calls" 2>/dev/null || fail "a status was posted on a head with no notes: $(cat "$STUB/gh-calls")"
  grep -qF "the notes draft, from the issues and commits since v1.0.0, is $ST/release/1.1.0.md. " <<<"$out" && grep -q 'run release-prep 1.1.0 again' <<<"$out" \
    || fail "release-prep does not print the draft's path and say to commit the notes and run again: $out"
  [ "$(cat "$ST/release/1.1.0.md")" = $'# 1.1.0\n\nCards can wait.\n\n## Cards\n\n- You can hold a card.' ] \
    || fail "the notes draft is not the model's: $(cat "$ST/release/1.1.0.md" 2>&1)"
  grep -q HOLD-BODY "$STUB/notes-prompt" && grep -q FAST-BODY "$STUB/notes-prompt" && grep -qx 'fix: A fix' "$STUB/notes-prompt" \
    && grep -qx 'feat(engine): A new thing' "$STUB/notes-prompt" \
    && grep -q '^- Begin with the line "# 1.1.0"' "$STUB/notes-prompt" && ! grep -q BEFORE-BODY "$STUB/notes-prompt" \
    || fail "the model was not given the issues and subjects since v1.0.0 alone, and the style: $(cat "$STUB/notes-prompt" 2>&1)"

  relmodel $'# 1.1.0\n\n- Cards can wait. Closes #5'
  out=$(loop release-prep 1.1.0 2>&1); [ $? = 1 ] || fail "release-prep did not stop on a head with no notes: $out"
  grep -qF 'The draft breaks the release notes style: ' <<<"$out" && grep -qF '1.1.0.md:3: a Closes line' <<<"$out" \
    || fail "release-prep does not say the draft breaks the style, naming the rule: $out"

  printf '#!/usr/bin/env bash\nexit 1\n' > "$STUB/claude"
  echo '# an earlier draft' > "$ST/release/1.1.0.md" || fail "the fixture could not be made"
  out=$(loop release-prep 1.1.0 2>&1); [ $? = 1 ] && grep -q 'the notes draft could not be written: the model gave no notes (exit 1' <<<"$out" \
    || fail "release-prep does not say the model gave no notes: $out"
  [ ! -e "$ST/release/1.1.0.md" ] || fail "a draft was written when the model gave none"
}

# The release notes style check, then release-prep on a head with notes.
# Bugs: the style check passes notes that name a file, an issue or a commit, so users read an engineering log; or it
# refuses the shipped 1.0.0 notes. Each finding names its rule, so the owner knows what to change. The suite runs, and
# its pass is posted, on a head whose notes `release` refuses, so the run is wasted. With the notes fixed: a passing
# status is posted on a commit whose suite was not run or did not pass, or on main's local head rather than the
# remote's (the commit `release` releases); a model is paid to draft notes the head already holds. Then a failing suite
# still posts a passing status, so `release` would release a red commit without running the suite.
t_relpass() {
  local O out f=$T/$CASE.md rule line
  # The 1.0.0 notes are checked where the release notes are: an install (closure.test.sh) ships no docs/releases/
  # folder, though it has the docs/ pages a test of the set reads (issue 769). The fixtures below run in both. A
  # checkout with docs/releases/ but no 1.0.0 notes still fails.
  if [ -d "$SRC/../docs/releases" ]; then
    out=$("$SRC/tools/notes-check.sh" "$SRC/../docs/releases/1.0.0.md") || fail "the 1.0.0 notes break the style: $out"
  else
    echo "skip [$CASE]: the 1.0.0 notes are not checked here: this install has no docs/releases/ folder" >&2
  fi
  while IFS='|' read -r rule line; do
    printf '# 9.9.9\n\nThe release.\n\n%s\n' "$line" > "$f"
    out=$("$SRC/tools/notes-check.sh" "$f" n.md); [ $? = 1 ] && grep -qF "n.md:5: $rule: $line" <<<"$out" \
      || fail "the check did not refuse \"$line\" as $rule: $out"
  done <<'EOF'
a ### heading|### Cards
an issue or pull request number|- Cards can wait (#12).
a commit hash|- Landed at 3f9a2c1d.
a path or file name|- The fix is in conveyor/lib/x.sh.
a path or file name|- The belt is drawn by belt3d.js.
a path or file name|- A new logo.svg and icon.png.
a Closes line|Closes #3
EOF

  relsetup true $'# 1.1.0\n\n### Fixes'
  out=$(loop release-prep 1.1.0 2>&1); [ $? = 1 ] && grep -qF 'docs/releases/1.1.0.md:3: a ### heading' <<<"$out" \
    || fail "release-prep did not refuse notes that break the style, naming the rule: $out"
  [ ! -e "$STUB/full-at" ] && ! grep -q statuses "$STUB/gh-calls" 2>/dev/null || fail "the suite ran or a status was posted on notes that break the style"

  # The notes fixed and pushed, and main one commit ahead of origin again.
  echo '- A fix' > "$R/docs/releases/1.1.0.md" && git -C "$R" commit -qam 'fix: The notes' && git -C "$R" push -q origin main \
    && O=$(git -C "$R" rev-parse HEAD) && git -C "$R" commit -q --allow-empty -m 'feat: Not pushed yet' || fail "the fixture could not be made"
  out=$(loop release-prep 1.1.0 2>&1) || fail "release-prep failed on a passing suite: $out"
  [ "$(cat "$STUB/full-at" 2>/dev/null)" = "$O" ] || fail "the suite did not run on origin's head $O: $(cat "$STUB/full-at" 2>&1)"
  [ "$(grep -c statuses "$STUB/gh-calls")" = 1 ] && grep -q "statuses/$O -f state=success -f context=conveyor/release-suite " "$STUB/gh-calls" \
    || fail "no passing conveyor/release-suite status was posted on $O: $(cat "$STUB/gh-calls" 2>&1)"
  [ ! -e "$STUB/sessions" ] && [ ! -e "$ST/release/1.1.0.md" ] || fail "a notes draft was written for a head that holds the notes"

  printf 'git rev-parse HEAD > "$STUB/full-at"\nfalse\n' > "$STUB/full-cmd" && rm -f "$STUB/full-at" "$STUB/gh-calls" || fail "the fixture could not be made"
  out=$(loop release-prep 1.1.0 2>&1); [ $? = 1 ] || fail "release-prep did not fail on a failing suite: $out"
  [ "$(cat "$STUB/full-at" 2>/dev/null)" = "$O" ] || fail "the suite did not run on origin's head $O"
  ! grep -q 'state=success' "$STUB/gh-calls" && grep -q "statuses/$O -f state=failure -f context=conveyor/release-suite " "$STUB/gh-calls" \
    || fail "a failing suite did not post a failing status, or posted a passing one: $(cat "$STUB/gh-calls" 2>&1)"
  grep -q 'suite failed' <<<"$out" || fail "release-prep does not say the suite failed: $out"
}

# cutsetup <full-cmd> [<text>]: for `release`. main's pack names a whole suite ($STUB/full-cmd, which notes the commit
# it ran on); main holds plugin.json (p, 1.0.0) and a marketplace whose entry for p is pinned at v1.0.0 (and another
# plugin's entry), and <text> in old.txt when given; v1.0.0 is tagged there, then a commit adds
# docs/releases/1.1.0.md; origin has main and the tag. gh: `api` reads print $STUB/statuses ([] when there is none);
# `api -X POST` and `release` are noted in $STUB/gh-calls, and the notes file `release` is given is kept as
# $STUB/body. O is main's head, the commit to release.
cutsetup() {
  setup '[]'; tune '.test.full = ". \"$STUB/full-cmd\""'
  printf 'git rev-parse HEAD > "$STUB/full-at"\n%s\n' "$1" > "$STUB/full-cmd"
  printf '%s\n' '#!/usr/bin/env bash' 'if [ "$1" = release ] || [[ " $* " == *" -X POST "* ]]; then printf "%s\n" "$*" >> "$STUB/gh-calls"' \
    'while [ $# -gt 0 ]; do [ "$1" != --notes-file ] || cp "$2" "$STUB/body"; shift; done' \
    'else cat "$STUB/statuses" 2>/dev/null || echo "[]"; fi' > "$STUB/gh"
  mkdir -p "$R/.claude-plugin" "$R/docs/releases" && jq -n '{name: "p", version: "1.0.0"}' > "$R/.claude-plugin/plugin.json" \
    && jq -n --arg s "$(printf 'a%.0s' {1..40})" '{name: "m", plugins: [{name: "p", source: {source: "url", url: "https://github.com/o/p.git", ref: "v1.0.0", sha: $s}},
      {name: "q", source: {source: "github", repo: "o/q", ref: "v9.0.0"}}]}' > "$R/.claude-plugin/marketplace.json" \
    && { [ -z "${2:-}" ] || echo "$2" > "$R/old.txt"; } \
    && git -C "$R" add -A && git -C "$R" commit -qm 'the first release' && git -C "$R" tag -a v1.0.0 -m 'Release 1.0.0' \
    && printf '# 1.1.0\n\n## Fixes\n\n- A fix\n' > "$R/docs/releases/1.1.0.md" && git -C "$R" add -A && git -C "$R" commit -qm 'fix: A fix' \
    && git -C "$R" push -q origin main v1.0.0 || fail "the fixture could not be made"
  O=$(git -C "$R" rev-parse HEAD)
}
# cutrefused <version> <reason (grep -E)>...: release exits 1 naming each reason, and nothing is committed, tagged,
# pushed or released. Bug each caller catches: a release cut when that check fails, or one refused that still changed
# something. The checks before the suite each add their reason, so one run can name several.
cutrefused() {
  local out h r v=$1; shift; h=$(git -C "$R" rev-parse HEAD)
  out=$(loop release "$v" 2>&1); [ $? = 1 ] || fail "release was not refused: $out"
  for r; do grep -qE "refused, nothing tagged or released: .*$r" <<<"$out" || fail "the refusal does not say why ($r): $out"; done
  [ "$(git -C "$R" rev-parse HEAD)" = "$h" ] && [ -z "$(git -C "$R" tag -l "v$v")" ] \
    || fail "a refused release committed or tagged: $(git -C "$R" log --oneline -3) $(git -C "$R" tag -l)"
  [ "$(git -C "$T/$CASE/origin" tag -l)" = v1.0.0 ] && [ "$(git -C "$T/$CASE/origin" rev-parse main)" = "$O" ] \
    && ! grep -q '^release' "$STUB/gh-calls" 2>/dev/null || fail "a refused release pushed or released: $(git -C "$T/$CASE/origin" tag -l) $(cat "$STUB/gh-calls" 2>&1)"
}

# release refused by the cheap checks, which come before the suite (not run when one of them refuses), then released.
# Refused: a version not higher than the newest release; no notes for it; an uncommitted change (which stays as it
# was); a commit the remote does not have, which would be released without being on GitHub's main. Bug: notes that read
# as an engineering log (an issue number here) are released as the GitHub release's text.
# Then all checks pass, with no status from release-prep: the suite runs; the tag is on a commit whose plugin.json says
# 1.1.0 and whose marketplace names v1.1.0; main's marketplace pins v1.1.0 at that commit, the other entry untouched;
# origin has both; the GitHub release is v1.1.0 with the notes as its body. The help says only the owner decides.
t_cutpass() {
  local O t out; cutsetup true
  echo changed >> "$R/a.txt" && git -C "$R" commit -q --allow-empty -m 'not pushed' || fail "the fixture could not be made"
  cutrefused 0.9.0 'the version 0.9.0 is not higher than the newest release, v1.0.0' 'no release notes: docs/releases/0.9.0.md is missing' \
    'the checkout has uncommitted changes' 'the checkout is not on main at the head of origin/main'
  [ "$(tail -n 1 "$R/a.txt")" = changed ] || fail "the refusal changed the uncommitted file"
  [ ! -e "$STUB/full-at" ] || fail "the suite ran for a release refused before it"

  git -C "$R" reset -q --hard "$O" && printf '# 1.1.0\n\n- A fix (#12)\n' > "$R/docs/releases/1.1.0.md" && git -C "$R" commit -qam 'the notes' \
    && git -C "$R" push -q origin main && O=$(git -C "$R" rev-parse HEAD) || fail "the fixture could not be made"
  cutrefused 1.1.0 'the release notes break the release notes style: docs/releases/1.1.0.md:3: an issue or pull request number'
  [ ! -e "$STUB/full-at" ] || fail "the suite ran for a release refused before it"

  printf '# 1.1.0\n\n## Fixes\n\n- A fix\n' > "$R/docs/releases/1.1.0.md" && git -C "$R" commit -qam 'the notes, fixed' \
    && git -C "$R" push -q origin main && O=$(git -C "$R" rev-parse HEAD) || fail "the fixture could not be made"
  out=$(loop release 1.1.0 2>&1) || fail "the release was refused: $out"
  [ "$(cat "$STUB/full-at" 2>/dev/null)" = "$O" ] || fail "the suite did not run on the commit to release"
  t=$(git -C "$T/$CASE/origin" rev-parse 'v1.1.0^{commit}' 2>/dev/null) && [ "$(git -C "$T/$CASE/origin" cat-file -t v1.1.0)" = tag ] \
    || fail "origin has no annotated tag v1.1.0"
  [ "$(git -C "$R" show "$t:.claude-plugin/plugin.json" | jq -r .version)" = 1.1.0 ] || fail "plugin.json's version at the tag is not 1.1.0"
  [ "$(git -C "$R" show "$t:.claude-plugin/marketplace.json" | jq -c '.plugins[0].source | [.ref, .sha]')" = '["v1.1.0",null]' ] \
    || fail "the marketplace at the tag does not name v1.1.0, or still pins the old sha"
  # The pin is written into the url source as it is: still a url source with its https:// URL, so it installs with no
  # GitHub SSH key.
  [ "$(git -C "$T/$CASE/origin" show main:.claude-plugin/marketplace.json | jq -c '[.plugins[].source | [.ref, .sha]]')" = "[[\"v1.1.0\",\"$t\"],[\"v9.0.0\",null]]" ] \
    && [ "$(git -C "$T/$CASE/origin" show main:.claude-plugin/marketplace.json | jq -c '.plugins[0].source | [.source, .url]')" = '["url","https://github.com/o/p.git"]' ] \
    && [ "$(git -C "$T/$CASE/origin" rev-parse main^)" = "$t" ] || fail "origin's main does not pin v1.1.0 at the tagged commit $t, right after it, in the same url source"
  grep -q '^release create v1.1.0 --verify-tag ' "$STUB/gh-calls" && cmp -s "$STUB/body" "$R/docs/releases/1.1.0.md" \
    || fail "the GitHub release is not v1.1.0 with the notes file as its body: $(cat "$STUB/gh-calls" 2>&1)"
  loop release --help | grep -q 'Only the owner decides a release: the Foreman runs conveyor.sh release only after the owner says yes in chat' \
    || fail "the help does not say only the owner decides a release"
}
# The privacy check, in one run: a private text in a tracked file from before the last release, which no commit since
# it touches; one added and removed again since the last release, still found by the commit that added it (h).
# Bug: a GitHub web edit's Signed-off-by trailer, which holds the commit's own author email, refused the release. A
# sign-off (A) or co-author (D) trailer with the commit's own author or committer email is not a hit; a sign-off with
# another email (B), or a body line with another email beside an own sign-off (C), still is. The hits are listed newest
# first, so the list is C B h exactly: A, D and the commit that removes the text are no hits.
t_cutprivacy() {
  local O h b c AT=@; local m=dev${AT}mail.io o=other${AT}mail.io; cutsetup true "someone${AT}gmail.com"
  echo "someone${AT}gmail.com" > "$R/new.txt" && git -C "$R" add new.txt && git -C "$R" commit -qm add && h=$(git -C "$R" rev-parse HEAD) \
    && git -C "$R" rm -q new.txt && git -C "$R" commit -qm remove || fail "the fixture could not be made"
  com() { GIT_COMMITTER_EMAIL=$1 git -C "$R" commit -q --allow-empty --author="dev <$m>" -m x -m "$2" && git -C "$R" rev-parse HEAD; } # <committer> <body>
  com "$m" "Signed-off-by: dev <DEV${AT}mail.io>" > /dev/null && b=$(com "$m" "Signed-off-by: other <$o>") \
    && c=$(com "$m" "$(printf 'Ask %s\n\nSigned-off-by: dev <%s>' "$o" "$m")") && com "$o" "Co-authored-by: other <$o>" > /dev/null \
    && git -C "$R" push -q origin main && O=$(git -C "$R" rev-parse HEAD) || fail "the fixture could not be made"
  cutrefused 1.1.0 'privacy check finds something in the tracked files.*old.txt:1: email' \
    "privacy check finds something in commits since v1.0.0: ${c:0:12} ${b:0:12} ${h:0:12} \(run"
}
# --allow-commit: hits in pushed commits (a, b) the owner keeps, as only a history rewrite could remove them.
# Bugs: no way to release over them; a named commit passes over a hit in one not named (b), or one not on origin/main
# (x, a commit main does not hold) is passed over too; the release does not keep which commits it passed over, and who
# said so; --allow-commit is taken with no --by.
t_cutallow() {
  local O a b x out AT=@; cutsetup true
  a=$(git -C "$R" commit -q --allow-empty -m "fix: ask someone${AT}gmail.com" && git -C "$R" rev-parse HEAD) \
    && b=$(git -C "$R" commit -q --allow-empty -m "fix: ask other${AT}gmail.com" && git -C "$R" rev-parse HEAD) \
    && x=$(git -C "$R" commit-tree -p "$b" -m "side: someone${AT}gmail.com" "$b^{tree}") \
    && git -C "$R" push -q origin main && O=$(git -C "$R" rev-parse HEAD) || fail "the fixture could not be made"
  out=$(loop release 1.1.0 --allow-commit "${a:0:12}" 2>&1); [ $? = 2 ] && grep -q 'usage: conveyor.sh release' <<<"$out" || fail "--allow-commit with no --by was taken: $out"
  out=$(loop release 1.1.0 --allow-commit "${a:0:12}" --by 'the owner' 2>&1); [ $? = 1 ] \
    && grep -q "privacy check finds something in commits since v1.0.0: ${b:0:12} (run" <<<"$out" || fail "a hit in a commit not named was passed over, or the named one still refused: $out"
  out=$(loop release 1.1.0 --allow-commit "${a:0:12}" --allow-commit "${b:0:12}" --allow-commit "${x:0:12}" --by 'the owner' 2>&1); [ $? = 1 ] \
    && grep -q "refused, nothing tagged or released: --allow-commit ${x:0:12}: ${x:0:12} is not on origin/main" <<<"$out" || fail "a named commit not on origin/main was not refused: $out"
  [ -z "$(git -C "$T/$CASE/origin" tag -l v1.1.0)" ] && ! grep -q '^release' "$STUB/gh-calls" 2>/dev/null || fail "a refused --allow-commit was tagged or released"
  out=$(loop release 1.1.0 --allow-commit "${a:0:12}" --allow-commit "${b:0:12}" --by 'the owner' 2>&1) || fail "the release with only named, pushed hits was refused: $out"
  grep -qF "passes over its hits in $b $a, on origin/main, by the owner" <<<"$out" && [ -n "$(git -C "$T/$CASE/origin" tag -l v1.1.0)" ] || fail "the release did not say what it passed over, or was not tagged: $out"
  jq -e --arg a "$a" --arg b "$b" '.state == "released" and .allowed == {by: "the owner", commits: [$b, $a]}' "$T/$CASE/cards/release/run.json" > /dev/null \
    || fail "the release's record does not keep the commits passed over and who said so: $(cat "$T/$CASE/cards/release/run.json")"
}
# The suite, the last check. Bugs: a release cut on a failing suite, or with the suite run on another commit than the one
# to release; a commit made in the checkout while the suite ran (a card landed there) tagged and pushed unchecked, or
# the run's record not saying main moved, so the Board's Release panel offers no run on the new main and shows no
# reason; a release-prep pass on the same commit not taken, and the whole suite run again.
t_cutsuite() {
  local O out; cutsetup false
  cutrefused 1.1.0 'the whole suite did not pass'
  [ "$(cat "$STUB/full-at" 2>/dev/null)" = "$O" ] || fail "the suite did not run on the commit to release"

  printf 'git rev-parse HEAD > "$STUB/full-at"\n%s\n' 'git -C "$R" commit -q --allow-empty -m "landed meanwhile"' > "$STUB/full-cmd" \
    || fail "the fixture could not be made"
  out=$(loop release 1.1.0 2>&1); [ $? = 1 ] && grep -q 'refused, nothing tagged or released: the checkout moved or changed while the suite ran' <<<"$out" \
    || fail "a checkout that moved during the suite was not refused: $out"
  [ -z "$(git -C "$R" tag -l v1.1.0)" ] && [ "$(git -C "$T/$CASE/origin" tag -l)" = v1.0.0 ] && [ "$(git -C "$T/$CASE/origin" rev-parse main)" = "$O" ] \
    && [ "$(git -C "$R" log -1 --format=%s)" = 'landed meanwhile' ] || fail "the refused release tagged, pushed or committed"
  jq -e --arg o "$O" '.moved == true and .state == "refused" and .sha == $o and .ended != null and any(.reasons[]; test("the checkout moved"))' "$T/$CASE/cards/release/run.json" > /dev/null \
    || fail "the run's record does not say main moved, with the moved reason: $(cat "$T/$CASE/cards/release/run.json" 2>&1)"

  git -C "$R" reset -q --hard "$O" && rm -f "$STUB/full-at" || fail "the fixture could not be made"
  echo '[{"context":"conveyor/release-suite","state":"success"},{"context":"conveyor/release-suite","state":"failure"}]' > "$STUB/statuses"
  out=$(loop release 1.1.0 2>&1) || fail "the release with release-prep's pass was refused: $out"
  [ ! -e "$STUB/full-at" ] && [ -n "$(git -C "$T/$CASE/origin" tag -l v1.1.0)" ] || fail "the suite ran again, or no tag was pushed: $out"
}
