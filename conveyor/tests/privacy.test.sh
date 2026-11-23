#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: privacy and GitHub writes.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# Bugs (plan section 8, P4 and P5): a finding holding a home path is posted on a public repo's issue; the held text
# is lost, or the card's reason does not say why nothing was posted; a private repo's (the host project's) comments
# stop posting; a write is made on a public repo whose named terms file cannot be read. The card is blocked here by
# its P1 finding coming back after its fix round, so its blocked comment, which quotes the finding, is held. (A
# follow-up of such a finding is filed masked: review.test.sh, t_privmask.)
t_privacy() {
  # The home path is put together here, as AT is, so this file holds none itself.
  local H=/home; local f="[P1] a.txt:1 reads $H/user/notes.txt" S a b; export XDG_CONFIG_HOME=$T/$CASE/config
  setup "[$(issue 7 2026-01-01)]"; S=$ST; for i in 1 2; do printf '%s\nUSER-VISIBLE: no\nVERDICT: NO-GO\n' "$f" > "$STUB/review.$i"; done
  mkdir -p "$XDG_CONFIG_HOME/conveyor"; echo 'case:Zed' > "$STUB/terms"; jq -n --arg t "$STUB/terms" '{terms: $t}' > "$XDG_CONFIG_HOME/conveyor/host.json"
  tune '.privacy.mode = "public"'
  loop run >/dev/null 2>&1
  [ ! -e "$STUB/comments" ] && [ ! -e "$STUB/filed" ] || fail "a public repo's issue got the home path: $(cat "$STUB/comments" "$STUB/filed" 2>&1)"
  st 'select(.step == "blocked") | .reason' | grep -q 'did not hold.*not posted on the issue: conveyor: privacy: nothing posted; the text is kept at <state>/privacy/[^:]*: line [0-9]*: home path' \
    || fail "the blocked reason does not say the privacy check held the comment: $(st 'select(.step == "blocked") | .reason')"
  [ "$(ls "$S/privacy" | wc -l)" = 1 ] && grep -q "reads $H/user/notes.txt" "$S/privacy"/* && grep -q '<state>/kept/' "$S/privacy"/* \
    && ! grep -q "$T" "$S/privacy"/* || fail "the held comment is not kept locally, or names an absolute path: $(ls "$S/privacy"; cat "$S/privacy"/*)"
}

# The checks of gh-write itself, a public pack's, with no run of the loop: each part is a case of its own (privwrite,
# privfiles, privjson), so they run side by side. privsetup: a public pack with its terms file (in the host file
# unless "none" is given), the case's home path in H and body files holding it.
privsetup() {
  H=/home; export XDG_CONFIG_HOME=$T/$CASE/config # the home path is put together here, as AT is, so this file holds none itself
  setup "[$(issue 7 2026-01-01)]"; mkdir -p "$XDG_CONFIG_HOME/conveyor"; echo 'case:Zed' > "$STUB/terms"
  [ "${1:-}" = none ] || jq -n --arg t "$STUB/terms" '{terms: $t}' > "$XDG_CONFIG_HOME/conveyor/host.json"
  tune '.privacy.mode = "public"'; printf 'reads %s\n' "$H/user/notes.txt" > "$T/$CASE/body"
  # api's --input is JSON, checked as GitHub decodes it: an escaped path is still a home path.
  printf '%s' '{"body":"reads \/home\/user\/notes.txt"}' > "$T/$CASE/body.json"
}
t_privwrite() {
  privsetup none
  # Bug (#630): the terms file is optional, yet a public repo with no host file (so no terms file) posted nothing at
  # all. With none, the check runs with no word list: a clean text posts, and a home path is still held.
  out=$(loop gh-write issue comment 7 --body hello 2>&1) && [ "$(cat "$STUB/comments")" = '7 --body hello' ] \
    || fail "a public repo with no terms file did not post a clean text: $out"
  out=$(loop gh-write issue comment 7 --body "$(cat "$T/$CASE/body")" 2>&1); [ $? = 3 ] && grep -q 'home path' <<<"$out" && [ "$(wc -l < "$STUB/comments")" = 1 ] \
    || fail "a public repo with no terms file posted a home path: $out"
  # A terms file the host file names and that cannot be read (a typo, a file moved) posts nothing: its terms are unknown.
  rm "$STUB/comments"; jq -n --arg t "$STUB/none" '{terms: $t}' > "$XDG_CONFIG_HOME/conveyor/host.json"
  out=$(loop gh-write issue comment 7 --body hello 2>&1); [ $? = 3 ] && grep -q "terms file cannot be read" <<<"$out" && [ ! -e "$STUB/comments" ] \
    || fail "a public repo's write went out with its named terms file unreadable: $out"
  # With a readable one, a clean text posts and a term is held, unnamed.
  jq -n --arg t "$STUB/terms" '{terms: $t}' > "$XDG_CONFIG_HOME/conveyor/host.json"
  loop gh-write issue comment 7 --body hello >/dev/null 2>&1 && [ "$(cat "$STUB/comments")" = '7 --body hello' ] || fail "a clean comment was not posted: $(cat "$STUB/comments" 2>&1)"
  # An option's value that looks like a file flag is text: it is posted, and no file is read.
  out=$(loop gh-write issue comment 7 --body -Foo 2>&1) && out=$(loop gh-write issue comment 7 --body --body-file=x 2>&1) \
    && [ "$(tail -2 "$STUB/comments")" = $'7 --body -Foo\n7 --body --body-file=x' ] || fail "a body that starts with a file flag was not posted: $out"
  sed -i '2,$d' "$STUB/comments"
  out=$(printf 'from Zed\n' | loop gh-write issue comment 7 --body-file - 2>&1); [ $? = 3 ] && grep -q 'line 5: private term (terms file line 1)' <<<"$out" \
    && ! grep -q Zed <<<"$out" && [ "$(wc -l < "$STUB/comments")" = 1 ] || fail "a private term was posted, or named in the refusal: $out"
}

# A body gh reads from a file is checked, in each form gh takes it. One comment is posted before (the count of
# comments then stays 1 when nothing more is posted).
t_privfiles() {
  privsetup; echo '7 --body hello' > "$STUB/comments"
  # Each form gh reads a file in: "<flag> " passes the file as the next argument, any other is joined to it.
  for a in '--body-file ' '-F ' '-wF ' '--body-file=' '-F' '-F=' 'api --field=body=@' 'api -Fbody=@' 'api -F=body=@' 'api --field body=@' \
    'api --input=' 'api --input '; do
    set -- issue comment 7; b=$T/$CASE/body; [[ $a != api* ]] || { set -- api repos/o/r/issues/7/comments; a=${a#api }; }
    [[ $a != --input* ]] || b=$b.json
    case $a in *' ') out=$(loop gh-write "$@" "${a% }" "$b" 2>&1) ;;
      *' '*) out=$(loop gh-write "$@" "${a%% *}" "${a#* }$b" 2>&1) ;;
      *) out=$(loop gh-write "$@" "$a$b" 2>&1) ;; esac
    [ $? = 3 ] && grep -q 'home path' <<<"$out" && [ "$(wc -l < "$STUB/comments")" = 1 ] || fail "a body read from a file ($a) was posted unchecked: $out"
  done
  # Bug: release create's --notes-file was passed to gh unread, so release notes were published with no check.
  out=$(loop gh-write release create v1 --notes-file "$T/$CASE/body" 2>&1); [ $? = 3 ] && grep -q 'home path' <<<"$out" || fail "release notes read from a file were posted unchecked: $out"
  out=$(loop gh-write release create v1 --notes-file="$T/$CASE/body" 2>&1); [ $? = 3 ] && grep -q 'home path' <<<"$out" || fail "release notes read from --notes-file= were posted unchecked: $out"
  # pr review's --comment, -c and -a are switches, so the file after them is still read; issue edit's -m takes a value.
  for a in --comment -c -a; do
    out=$(loop gh-write pr review 7 "$a" --body-file="$T/$CASE/body" 2>&1); [ $? = 3 ] && grep -q 'home path' <<<"$out" || fail "pr review $a hid a body file from the check: $out"
  done
  out=$(loop gh-write pr review 7 -cF "$T/$CASE/body" 2>&1); [ $? = 3 ] && grep -q 'home path' <<<"$out" || fail "pr review -cF hid a body file from the check: $out"
}

# A value option's text that starts with a file flag is no file; a JSON or GraphQL body is checked as GitHub decodes
# it. One comment is posted before, as in privfiles.
t_privjson() {
  privsetup; echo '7 --body hello' > "$STUB/comments"
  out=$(loop gh-write issue edit 7 -m -Foo 2>&1) || fail "a milestone that starts with -F was read as a file: $out"
  # A group of short options gives its value option the next argument (-cb <text>), and an alias (new) its options.
  out=$(loop gh-write pr review 7 -cb -Foo 2>&1) || fail "pr review -cb's body that starts with -F was read as a file: $out"
  out=$(loop gh-write issue new --title t --body b -m -Foo 2>&1) || fail "issue new's milestone that starts with -F was read as a file: $out"
  # A repository option before the command leaves the command's own value options in force, and api still api.
  out=$(loop gh-write --repo o/r issue close 7 --comment -Foo 2>&1) || fail "issue close's comment after --repo was read as a file: $out"
  out=$(loop gh-write -R o/r api repos/o/r/issues/7/comments -Fbody=@"$T/$CASE/body" 2>&1); [ $? = 3 ] && grep -q 'home path' <<<"$out" \
    || fail "api's body file after -R was posted unchecked: $out"
  out=$(loop gh-write api repos/o/r/issues/7/comments --input - < "$T/$CASE/body.json" 2>&1); [ $? = 3 ] && grep -q 'home path' <<<"$out" \
    && [ "$(wc -l < "$STUB/comments")" = 1 ] || fail "an escaped home path in JSON on standard input was posted: $out"
  # A decoded NUL does not make the check skip the text as binary.
  out=$(printf '%s' '{"body":"\/home\/user\/notes.txt","unused":"\u0000"}' | loop gh-write api repos/o/r/issues/7/comments --input - 2>&1)
  [ $? = 3 ] && grep -q 'home path' <<<"$out" && [ "$(wc -l < "$STUB/comments")" = 1 ] || fail "a home path beside a decoded NUL was posted: $out"
  # A surrogate pair decodes as the one character GitHub posts, so a term that holds it is still found.
  printf 'case:Acme\360\220\220\200\n' >> "$STUB/terms"
  out=$(printf '%s' '{"body":"Acme\ud801\udc00"}' | loop gh-write api repos/o/r/issues/7/comments --input - 2>&1)
  [ $? = 3 ] && grep -q 'private term (terms file line 2)' <<<"$out" && [ "$(wc -l < "$STUB/comments")" = 1 ] || fail "a term escaped as a surrogate pair was posted: $out"
  sed -i '2,$d' "$STUB/terms"
  # GraphQL decodes its own escapes inside the query JSON carries, and a -f query is GraphQL alone.
  out=$(jq -nc --arg b '\u002fhome\u002fuser\u002fnotes.txt' '{query: ("mutation { addComment(input: {subjectId: \"I\", body: \"" + $b + "\"}) { clientMutationId } }")}' \
    | loop gh-write api graphql --input - 2>&1); [ $? = 3 ] && grep -q 'home path' <<<"$out" || fail "a GraphQL-escaped home path in JSON was posted: $out"
  out=$(loop gh-write api graphql -f query='mutation { addComment(input: {subjectId: "I", body: "\u{2f}home\u{2f}user"}) { clientMutationId } }' 2>&1)
  [ $? = 3 ] && grep -q 'home path' <<<"$out" || fail "a GraphQL-escaped home path in a -f query was posted: $out"
  out=$(printf 'hello' | loop gh-write api markdown/raw --method POST --header 'Content-Type: text/plain' --input - 2>&1) || fail "a clean body that is not JSON was refused: $out"
  out=$(loop gh-write issue comment 7 --body-file "$T/$CASE/none" 2>&1); [ $? = 3 ] && [ "$(wc -l < "$STUB/comments")" = 1 ] || fail "an unreadable body file was posted: $out"
}

# Bug (#1486): with the host file naming a terms file that cannot be read, privwords() ran the check with no terms and
# passed, so privmask() left a term in a public card's Rollout lines (cardready(), lib/cardland.sh) and the commit
# carried it. Now the check fails, and the card is blocked. With the file readable, the same line has the term masked.
t_privterms() {
  privsetup; local ro='Open port 22 to Zed | the deploy fails | a.txt:2' h
  fx_in "privmask '$ro'"
  [ "$RC" = 0 ] && [ "$(cat "$T/$CASE/run.out")" = 'Open port 22 to <private term> | the deploy fails | a.txt:2' ] \
    || fail "privmask '$ro' with a readable terms file did not mask the term (exit $RC): $(cat "$T/$CASE/run.out")"
  # Each host file names a terms file that cannot be read (<stub>/none is missing, <stub>/empty is readable and empty).
  # Bugs: the shell dropped a line break at the end of the name (h1) or a NUL byte in it (h2), so <stub>/empty was read
  # in place of the file named; of a host file of two values, the first named the file, and the second named
  # <stub>/empty (h3, termsfile()) or no file (h4, termsnamed()); each time the check passed with no terms.
  : > "$STUB/empty"; mkdir "$T/$CASE/hosts"
  jq -n --arg t "$STUB/none" '{terms: $t}' > "$T/$CASE/hosts/h0"
  jq -n --arg t "$STUB/empty" '{terms: ($t + "\n")}' > "$T/$CASE/hosts/h1"
  jq -n --arg t "$STUB/em" '{terms: ($t + "\u0000pty")}' > "$T/$CASE/hosts/h2"
  jq -n --arg t "$STUB" '{terms: ($t + "/none\n")}, {terms: ($t + "/empty")}' > "$T/$CASE/hosts/h3"
  jq -n --arg t "$STUB/none" '{terms: $t}, {}' > "$T/$CASE/hosts/h4"
  for h in "$T/$CASE"/hosts/h*; do
    cp "$h" "$XDG_CONFIG_HOME/conveyor/host.json"; fx_in "privmask '$ro'"
    [ "$RC" != 0 ] && grep -q "terms file cannot be read" "$T/$CASE/run.out" && ! grep -q Zed "$T/$CASE/run.out" \
      || fail "privmask '$ro' with the host file ${h##*/} $(jq -c . "$h" | paste -sd ' ' -) did not fail, or printed the term (exit $RC): $(cat "$T/$CASE/run.out")"
  done
}

# A private pack (the test pack's mode): the finding t_privacy holds is posted and filed, with a warning that names no
# matched text.
t_privprivate() {
  local H=/home; local f="[P2] a.txt:1 reads $H/user/notes.txt" # the home path is put together here, as AT is
  setup "[$(issue 7 2026-01-01)]"; for i in 1 2 3; do printf '%s\nUSER-VISIBLE: no\nVERDICT: NO-GO\n' "$(moved "${i/3/}" "$f")" > "$STUB/review.$i"; done
  [ "$(bash "$SRC/lib/pack.sh" get privacy.mode "$R/.conveyor/project.json")" = private ] || fail "the test pack is not in private mode"
  # loop: only a whole card files its review's findings as follow-ups when its reviews run out, the warning in its output
  out=$(loop run 2>&1) || fail "run exited non-zero: $out"
  grep -q "reads $H/user/notes.txt" "$STUB/filed" && [ "$(st 'select(.step == "landed") | .issue')" = 7 ] || fail "a private repo's follow-up was not filed: $(cat "$STUB/filed" 2>&1)"
  grep -q 'privacy warning .*line [0-9]*: home path' <<<"$out" && ! grep -q 'privacy warning.*notes\.txt' <<<"$out" || fail "no privacy warning, or it names the match: $out"
}

# The privacy check (P4): every generic pattern and a term is found by file and line and named, never printed; a
# noreply address, a version number and a term that is only part of a word are not hits.
t_privcheck() {
  # The hits are put together here, as AT is, so this file holds none itself.
  local c=$SRC/privacy/check.sh d=$T/$CASE out H=/home U=/Users day=20000101; mkdir -p "$d"
  ip() { local IFS=.; echo "$*"; }
  # Bug (#636): CI's privacy step failed on every run on test commits by t@example.com and the demo's /home/dev, which
  # are not private: an address at a domain reserved for examples (lines 16, 17) and the demo's neutral user dev
  # (lines 18, 19) are not hits; a real address and user are (2, 8), and so are look-alikes (20 to 22), each of
  # them a hit even beside an exception on its line.
  printf '%s\n' 'clean' "someone${AT}gmail.com" "x${AT}users.noreply.github.com" "$(ip 10 1 2 3)" "$(ip 172 20 0 1)" "$(ip 192 168 1 252)" 'v1.10.1.2.3' "$H/alice/x" "$U/user" \
    "r-$day-000000-p" "ghp_$(printf 'a%.0s' $(seq 36))" 'Zed said' 'zed' 'Zedd' 'Ann' \
    "user.email=t${AT}example.com" "x${AT}ci.example.org, y${AT}EXAMPLE.NET." "$H/dev/x and $U/dev." "-d $H/dev -s; sed 's|$H/dev|~|g'" \
    "t${AT}example.com and x${AT}example.com.mail.io" "x${AT}notexample.com" "$H/dev/x then $H/devops/x, $H/dev.bob and '$H/alice'" > "$d/f"
  printf 'case:Zed\n# a note\n\nann\nnowhere\n' > "$d/terms"
  out=$("$c" --terms "$d/terms" "$d/f"); [ $? = 1 ] || fail "hits did not exit 1"
  [ "$out" = "$(printf '%s\n' "$d/f:2: email" "$d/f:20: email" "$d/f:21: email" "$d/f:4: private address" "$d/f:5: private address" "$d/f:6: private address" \
    "$d/f:8: home path" "$d/f:9: home path" "$d/f:22: home path" "$d/f:10: ruling id" "$d/f:11: token" "$d/f:12: private term (terms file line 1)" \
    "$d/f:15: private term (terms file line 4)")" ] || fail "hits: $out"
  [ "$(echo clean | "$c")" = '' ] && echo clean | "$c" || fail "a clean text is a hit"
  printf 'a\0b\n%s\n' "$H/user/x" > "$d/nul"; [ "$("$c" "$d/nul")" = "$d/nul:2: home path" ] || fail "a file holding a NUL was not checked"
  # Bug (#131): the release was refused on a test's fake home <case>/home/.claude, read as a user's home. A folder after
  # /home/ or /Users/ that starts with a dot is no user's (1, 3); a user's path is still a hit, with a dot folder in it (2) or not (4).
  printf '%s\n' "$H/.claude" "$H/alice/.claude" "$U/.config" "$U/bob" > "$d/dot"
  [ "$("$c" "$d/dot")" = "$(printf '%s\n' "$d/dot:2: home path" "$d/dot:4: home path")" ] || fail "dot folders: $("$c" "$d/dot")"
  "$c" --terms "$d/none" "$d/f" >/dev/null 2>&1; [ $? = 2 ] || fail "an unreadable terms file is not exit 2"
  "$c" --terms "$d" "$d/f" >/dev/null 2>&1; [ $? = 2 ] || fail "a directory as the terms file is not exit 2"
  "$c" "$d" >/dev/null 2>&1; [ $? = 2 ] || fail "a directory to check is not exit 2"
  # Bug: the release's CI privacy step failed on the demo GIF and MP4, whose compressed bytes read as emails. In a
  # media file an email-like run of bytes is not a hit; a home path and a private term still are.
  printf 'GIF89a\0x%s\n%s\nZed\n' "Q${AT}fs.gt" "$H/alice/x" > "$d/a.GIF"
  [ "$("$c" --terms "$d/terms" "$d/a.GIF")" = "$(printf '%s\n' "$d/a.GIF:2: home path" "$d/a.GIF:3: private term (terms file line 1)")" ] \
    || fail "media: $("$c" --terms "$d/terms" "$d/a.GIF")"
  printf '%s\n' "Q${AT}fs.gt" > "$d/a.txt"; [ "$("$c" "$d/a.txt")" = "$d/a.txt:1: email" ] || fail "an email in a text file was not a hit"
}

# Bug (#783): release 1.6.0 was refused on a Board test's SWE-bench task ID, task-django__django-15347, whose "sk-..."
# read as a secret key. A task ID, with its task- prefix (1) or without (2), is not a hit; an sk- key on its own (3),
# after = (4) or in quotes (5) still is.
t_privswebench() {
  local c=$SRC/privacy/check.sh d=$T/$CASE k; mkdir -p "$d"; k="sk-$(printf 'a%.0s' $(seq 24))"
  printf '%s\n' "act(bp(w), 'task-django__django-15347')" 'astropy__astropy-12907' "$k" "KEY=$k" "\"$k\"" > "$d/f"
  [ "$("$c" "$d/f")" = "$(printf '%s\n' "$d/f:3: token" "$d/f:4: token" "$d/f:5: token")" ] || fail "task IDs and keys: $("$c" "$d/f")"
  "$c" "$SRC/../.claude/scripts/__tests__/dashboard-view.bench-pages.test.mjs" || fail "the Benchmarks tab test is a hit"
}

# Bug: the release was refused on docs that name git${AT}github.com, a git SSH address, not a person's email. A git SSH
# address (lines 1 to 4) is not a hit; a person's address at those hosts (5, 6), and git${AT} at another host with no
# colon or ssh:// (7), still are, as is an address beside an SSH address on its line (8). An example address before a
# colon (9) still passes.
t_privssh() {
  local c=$SRC/privacy/check.sh f=$T/$CASE/f out; mkdir -p "$T/$CASE"
  printf '%s\n' "fails with git${AT}github.com: Permission denied" "clone git${AT}codeberg.org:o/r.git" "ssh://git${AT}git.sr.ht/~o/r" \
    "git${AT}gitlab.com" "someone${AT}github.com" "ssh://someone${AT}gitlab.com/o/r" "git${AT}corp.io" \
    "git${AT}github.com:o/r by someone${AT}gmail.com" "t${AT}example.com: the test user" > "$f"
  out=$("$c" "$f"); [ "$out" = "$(printf '%s\n' "$f:5: email" "$f:6: email" "$f:7: email" "$f:8: email")" ] || fail "hits: $out"
}

# Bug (#275): the 1.4.0 release was refused on busy.test.sh's cgroup path /user.slice/user${AT}1000.service/app.slice,
# a systemd instance unit name read as an email. A unit name (lines 1 to 3) is not a hit; a real address beside one on
# its line (4) and an address at a real domain (5) still are.
t_privunit() {
  local c=$SRC/privacy/check.sh f=$T/$CASE/f out; mkdir -p "$T/$CASE"
  printf '%s\n' "s=/user.slice/user${AT}1000.service/app.slice" "getty${AT}tty1.service and systemd-fsck${AT}dev-sda1.service: ok, sshd${AT}3.socket" \
    "a${AT}b.timer, c${AT}d.mount, e${AT}f.target, g${AT}h.path, i${AT}j.scope, k${AT}l.slice" \
    "user${AT}1000.service by someone${AT}gmail.com" "someone${AT}service.io" > "$f"
  out=$("$c" "$f"); [ "$out" = "$(printf '%s\n' "$f:4: email" "$f:5: email")" ] || fail "hits: $out"
}

# Bug (#329): the 1.5.0 release was refused on swebench.test.sh's HF_HOME="$C/home/hf", a folder named home under the
# case's temp folder read as a user's home. A home or Users folder after a shell variable, a closing } or ), or
# another path part (lines 1 to 3) is not a hit; at the start of a path, after a space, a quote, = or : (4 to 7), and
# beside a non-hit on its line (8), it still is. Right after the exempt dev home, past the : or quote its match ends
# on (9, 10), it is a hit too: a match that took the character before its slash hid the next path.
t_privnested() {
  local c=$SRC/privacy/check.sh f=$T/$CASE/f out H=/home U=/Users; mkdir -p "$T/$CASE"
  printf '%s\n' "HOME=\"\$C$H\" HF_HOME=\"\$C$H/hf\" \${T}$U/a \$C$H$H/x" "tmp$H/x and \$(pwd)$U/x" "a-b_c.d$H/x" \
    "$H/alice/x" "cd $U/bob" "\"$H/a\" '$U/b'" "HOME=$H/a PATH=/bin:$H/a/bin" "\$C$H/hf then $H/alice" \
    "PATH=$H/dev:$H/alice/bin" "[\"$H/dev\",\"$H/alice\"]" > "$f"
  out=$("$c" "$f"); [ "$out" = "$(for l in 4 5 6 7 8 9 10; do echo "$f:$l: home path"; done)" ] || fail "hits: $out"
}

# P5: every GitHub write the engine and the Board make goes through gh_write (conveyor.sh gh-write): a gh write
# anywhere else in them is a fail. A gh api call is allowed only as a graphql read.
t_ghwrite() {
  local f files=("$SRC"/*.sh "$SRC"/*.py "$SRC"/lib/*.sh "$SRC"/privacy/*.sh "$SRC"/jq/* "$SRC"/../.claude/scripts/dashboard*) out=''
  # gh, then any options before the command (gh --repo o/r issue comment ...), then the command.
  local g='gh([[:space:]]+-[^[:space:]]*([[:space:]]+[^-[:space:]][^[:space:]]*)?)*[[:space:]]+'
  local w="$g(issue|pr)[[:space:]]+(comment|edit|create|close|reopen|delete|transfer|lock|unlock|pin|unpin|merge|review)|$g(label|release|repo)[[:space:]]+(create|edit|delete|upload|clone)"
  # The lines of <file> the scan flags: a write, or a gh api call that is no graphql read.
  flagged() {
    grep -nHE "$w" "$1"
    if grep -qE "${g}api" "$1"; then
      grep -nHE "${g}api" "$1" | grep -vE "${g}api[[:space:]]+graphql" || :
      grep -nHE "${g}api.*(-X|--method)|mutation" "$1" || :
    fi
  }
  for f in "${files[@]}"; do
    [ "$f" != "$SRC/conveyor.test.sh" ] || continue
    out+=$(flagged "$f")
  done
  [ -z "$out" ] || fail "a GitHub write outside gh_write: $out"
  # The examples go through the same scan (#1435: they were matched against `gh api` alone, which a graphql read matches
  # too, so a scan that flagged every gh api call passed). The last flagged: a REST read. A graphql read is not flagged.
  mkdir -p "$T/$CASE"; f=$T/$CASE/example
  for x in 'gh --repo owner/repo issue comment 7 --body x' 'gh -R o/r pr edit 1' 'gh --repo o/r api repos/o/r/issues'; do
    printf '%s\n' "$x" > "$f"; [ -n "$(flagged "$f")" ] || fail "the guard misses: $x"
  done
  x="gh api graphql -f query='{ repository(owner: \"o\", name: \"r\") { issue(number: 7) { id } } }'"
  printf '%s\n' "$x" > "$f"; [ -z "$(flagged "$f")" ] || fail "the guard flags a graphql read: $x"
}
