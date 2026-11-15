#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# What the README (the front page) holds: its sections in order, no OWNER placeholder, and CONTRIBUTING.md,
# CODE_OF_CONDUCT.md and SECURITY.md there and linked (the engine reference and the issue forms from CONTRIBUTING.md);
# the brand, badges, diagram and demo GIF shown, and each file the README links or shows in the repo. Its Install, Set
# up and Start parts are the user's steps alone: at most one code block, and no host file, terms file, CONVEYOR_MAIN or
# clone, which setup does (conveyor/tests/setup.test.sh, setupfresh, runs it so). And what the pages hold (the README
# and docs/*.md, which the README links for the rest): each part of the belt, every command conveyor.sh takes, named,
# and each slash command they name one of the plugin's commands.
set -uo pipefail
SRC=$(cd "$(dirname "$0")" && pwd -P)
fail() { echo "FAIL [readme]: $*" >&2; exit 1; }

# A reader finds each part of the belt named on a page, the sections in the front page's order, the real account in
# the install commands (not a placeholder), and the Contributing, Code of conduct and security policy files and the
# issue forms (bug: a reporter finds no private way to report a vulnerability).
R=$SRC/README.md
PAGES=("$R" "$SRC"/docs/*.md)
want='Requirements Install Set_up Start The_Board Tests /units Foreman License'
got=$(sed -n 's/^## //p' "$R" | tr ' ' _ | grep -xF -f <(tr ' ' '\n' <<<"$want") | tr '\n' ' ')
[ "${got% }" = "$want" ] || fail "the README's sections are not, in this order: $want (it has: $got)"
# Bug (#638): the front page did not name the Tests page, one of the Board's main parts. Its Tests section links it.
awk '/^## / { on = ($0 == "## Tests"); next } on' "$R" | grep -qF '](docs/board.md#tests-page)' \
  || fail "the README's Tests section does not link docs/board.md#tests-page"
! grep -qw OWNER "$R" || fail "the README still says OWNER where the account name belongs"
for s in 'judge' 'Declined' 'with no second run' '/conveyor-belt:foreman' 'setup --foreman' 'lane fast review' \
  'lane fast land' 'lane fast reset' 'Research lane**, read-only' '/conveyor-belt:review' '/conveyor-belt:away' \
  'control hold' 'control release' 'conveyor.sh retry' 'Users and authenticator codes' 'Accounts' 'API proxy' 'Belt 3D' \
  'Depends on: #N' 'waiting list' 'Dependency guard' 'control dep-guard off' 'control force <issue>' 'Queue anyway' \
  'control reviewer opencode ' 'opencode auth login' 'codex debug models' 'conveyor.sh clis' \
  '`history` prints, whole, the lists the snapshot cuts'; do # bug: a reader cannot find the cut lists' full history
  grep -qF -- "$s" "${PAGES[@]}" || fail "no page names: $s"
done
for f in CONTRIBUTING.md CODE_OF_CONDUCT.md SECURITY.md; do
  [ -s "$SRC/$f" ] && grep -qF "]($f)" "$R" || fail "$f is missing, or the README does not link it"
done
# Pages for contributors, not users, are reached from CONTRIBUTING.md (bug: an engine reference or issue form no page links).
for f in conveyor/README.md .github/ISSUE_TEMPLATE/; do
  [ -e "$SRC/$f" ] && grep -qF "]($f)" "$SRC/CONTRIBUTING.md" || fail "$f is missing, or CONTRIBUTING.md does not link it"
done
grep -q 'Contributor Covenant' "$SRC/CODE_OF_CONDUCT.md" || fail "the code of conduct is not the Contributor Covenant"
# The visuals: the brand, the badges, the diagram and the demo GIF are shown. Bug: a picture dropped from the README.
for s in 'src="docs/brand.svg"' 'src="https://img.shields.io/' 'src="docs/how-it-works.svg"' 'src="docs/demo.gif"'; do
  grep -qF -- "$s" "$R" || fail "the README does not show: $s"
done
# Bug (#641): the Belt 3D GIF missing, moved away from the diagram, or shown with no alt text. It is the picture
# directly before the diagram, and its alt text says what it shows.
pics=$(grep -oE '<img [^>]*src="docs/[^"]+"[^>]*>' "$R")
before=$(grep -B1 -F 'src="docs/how-it-works.svg"' <<<"$pics" | head -1)
grep -qF 'src="docs/belt-3d.gif"' <<<"$before" || fail "the picture directly before docs/how-it-works.svg is not docs/belt-3d.gif"
grep -qE 'alt="[^"]{20,}"' <<<"$before" || fail "docs/belt-3d.gif has no alt text that says what it shows"
# Each file the README links or shows is in the repo. Bug: a link or picture to a file that was moved or never added.
while read -r f; do
  [ -e "$SRC/$f" ] && [ -n "$(git -C "$SRC" ls-files -co --exclude-standard -- "$f")" ] || fail "the README links $f, which the repo does not have"
done < <(grep -oE '(src|href)="[^"]+"|\]\([^)]+\)' "$R" | sed -E 's/^(src|href)="//; s/"$//; s/^\]\(//; s/\)$//; s/#.*//' \
  | grep -vE '^(https?:|mailto:|$)' | sort -u)
# Every command conveyor.sh takes (a line of its command table, `cmd <command> ...`) is named on a page. Bug: a
# command added to the engine and never documented.
cmds=$(sed -nE 's/^cmd ([a-z][a-z-]*) .*/\1/p' "$SRC/conveyor/conveyor.sh"); [ -n "$cmds" ] || fail "conveyor.sh's command table was not read"
while read -r c; do
  grep -qE "\`(conveyor\.sh )?${c}[ \`]" "${PAGES[@]}" || fail "no page names the command conveyor.sh $c"
done <<<"$cmds"
# Bug (#630): the user's steps on the front page asked for a clone, a host file and a terms file written by hand, and
# a foreground run with CONVEYOR_MAIN, which setup does or the docs hold. Install, Set up and Start together: at most
# one code block, and none of those. Nor conveyor.sh: setup does not put it on PATH, so a bare `conveyor.sh` command
# there fails with "command not found" on a fresh machine.
steps=$(awk '/^## / { on = ($0 ~ /^## (Install|Set up|Start)$/); next } on' "$R")
[ -n "$steps" ] || fail "the README has no Install, Set up or Start part"
[ "$(grep -c '^```' <<<"$steps")" -le 2 ] || fail "the README's Install, Set up and Start parts hold more than one code block"
for s in host.json terms CONVEYOR_MAIN 'git clone' conveyor.sh; do
  ! grep -qF -- "$s" <<<"$steps" || fail "the README's Install, Set up and Start parts name $s"
done
# Bug (#635): the Board's page installed it by a clone of its own and four commands; `conveyor.sh board` does it
# (conveyor/tests/install.test.sh, board, runs it on a fixture).
b=$(awk '/^## / { on = ($0 == "## Install the Board"); next } on' "$SRC/docs/board.md")
grep -qF 'conveyor.sh board' <<<"$b" && ! grep -qF 'git clone' <<<"$b" || fail "docs/board.md does not install the Board by conveyor.sh board alone"
# Each plugin command the pages name is one the plugin has.
while read -r c; do
  [ -f "$SRC/commands/${c#/conveyor-belt:}.md" ] || fail "a page names $c, which the plugin does not have"
done < <(cat "${PAGES[@]}" | grep -oE '/conveyor-belt:[a-z-]+' | sort -u)
echo "ok readme"
