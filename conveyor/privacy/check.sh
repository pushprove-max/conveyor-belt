#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# The privacy check (plan docs/plans/conveyor-plugin-2026-11-10.md, section 8, P4).
# Usage: check.sh [--terms <file>] [<file>...]   (no file: standard input, named -)
# Prints one line per hit, <file>:<line>: <pattern name>, never the matched text; exit 0 with no hit, 1 with any,
# 2 when a file or the terms file cannot be read (a directory cannot).
# The terms file holds one private term per line (blank lines and lines starting with # are skipped). A term matches
# as a whole word, case-insensitively; a line starting with `case:` holds a term matched case-sensitively, for a word
# that is also code (`case:Ann` matches Ann, not ann). A term's hit is named by its line in the terms file, never by
# the term.
set -uo pipefail
usage() { echo "usage: check.sh [--terms <file>] [<file>...]" >&2; exit 2; }
terms=''
[ "${1:-}" != --terms ] || { [ $# -ge 2 ] || usage; terms=$2; shift 2; }
[ -z "$terms" ] || { [ -r "$terms" ] && [ ! -d "$terms" ]; } || { echo "privacy: the terms file cannot be read" >&2; exit 2; }

# name<TAB>extended regular expression, matched with grep -E. An email is a hit unless it holds "noreply" or is at a
# domain reserved for examples (example.com, example.org, example.net or a subdomain of one, RFC 2606) or is a git SSH
# address, not a person's: git@ after ssh://, git@<host> before a colon, or git@<host> alone where the host is
# github.com or gitlab.com (any other user at those hosts is still a hit), or is a systemd instance unit name
# (<name>@<instance>.service, also .slice, .socket, .scope, .target, .mount, .timer or .path), not an address. A home path is
# a hit unless its user is dev, the neutral user of the demo's container (docs/demo/record-terminal.sh). A folder after
# /home/ or /Users/ that starts with a dot (/home/.claude) is no user's home, as no user name starts with a dot. A
# /home/ or /Users/ right after a shell variable, a closing } or ) or another path part ($C/home/hf, ${T}/Users/a,
# tmp/home/x) is a folder under that path, not an absolute home path; at the start of a path, after a space, a quote,
# = or : it is still a hit. An sk- key starts a word: sk- right after a letter or digit is part of another word, as in a
# SWE-bench task ID (task-django__django-15347), not a key.
PATTERNS=$'email\t[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}
private address\t(^|[^0-9.])(10\\.[0-9]{1,3}|192\\.168|172\\.(1[6-9]|2[0-9]|3[01]))\\.[0-9]{1,3}\\.[0-9]{1,3}($|[^0-9])
home path\t/(Users|home)/[^./[:space:]][^/[:space:]]*
ruling id\tr-[0-9]{8}-[0-9]{6}-
token\t(gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{20,}|AKIA[0-9A-Z]{16}|(^|[^A-Za-z0-9])sk-[A-Za-z0-9_-]{20,}|xox[abprs]-[A-Za-z0-9-]{10,}|-----BEGIN [A-Z ]*PRIVATE KEY-----)'

T=$(mktemp) || exit 2; trap 'rm -f "$T"' EXIT
hit=0
# grep -a: a file holding a NUL or bytes that are not text is still searched line by line; without it grep reports
# only "binary file matches", and every hit in the file is missed.
one() { # <file> <name shown>
  local name rx n t l
  while IFS=$'\t' read -r name rx; do
    # Each match alone (grep -o, as <line>:<match>), so an exception passes over that match, never its whole line.
    # Compressed media (GIF, MP4, PNG, JPEG, WebM, WebP) hold random bytes that read as emails; what they show is
    # checked by OCR where they are made (docs/demo/make.sh). The other patterns and the terms still apply to them.
    if [ "$name" = email ] && [[ ${2,,} =~ \.(gif|mp4|png|jpe?g|webm|webp)$ ]]; then
      :
    elif [ "$name" = email ]; then
      # Each match is taken with the ssh:// before it and the colon after it, where there is one, to tell an SSH address.
      grep -anoE -- "(ssh://)?$rx:?" "$1" | grep -vi noreply | grep -viE '@([a-z0-9-]+\.)*example\.(com|org|net):?$' \
        | grep -vE '^[0-9]+:(ssh://git@|git@[^:]+:$|git@(github\.com|gitlab\.com)$)' \
        | grep -vE '^[0-9]+:[^@]+@[^@]*\.(service|slice|socket|scope|target|mount|timer|path):?$' | cut -d: -f1
    elif [ "$name" = 'home path' ]; then
      # A nested home or Users folder is renamed (home_) first, so the pattern needs no character before the slash:
      # a match that took that character would take it from the next path too (the : between the exempt dev home and
      # another user's home in one PATH value).
      LC_ALL=C sed -E ':a
s#([A-Za-z0-9_.~$})*-])/(Users|home)/#\1/\2_/#g
ta' "$1" | grep -anoE -- "$rx" | grep -vE '^[0-9]+:/(Users|home)/dev\.*([^A-Za-z0-9._-].*)?$' | cut -d: -f1
    else
      grep -anE -- "$rx" "$1" | cut -d: -f1
    fi | sort -nu | while read -r l; do echo "$2:$l: $name"; done
  done <<<"$PATTERNS"
  [ -n "$terms" ] || return 0
  n=0
  while IFS= read -r t || [ -n "$t" ]; do
    n=$((n + 1))
    case $t in '' | '#'*) continue ;; esac
    case $t in case:*) grep -anwF -- "${t#case:}" "$1" ;; *) grep -anwiF -- "$t" "$1" ;; esac \
      | cut -d: -f1 | while read -r l; do echo "$2:$l: private term (terms file line $n)"; done
  done < "$terms"
}
[ $# -gt 0 ] || set -- -
for f; do
  if [ "$f" = - ]; then cat > "$T" || exit 2; src=$T; else { [ -r "$f" ] && [ ! -d "$f" ]; } || { echo "privacy: $f cannot be read" >&2; exit 2; }; src=$f; fi
  out=$(one "$src" "$f") # grep's no-match exit is not an error: each file was checked readable above
  [ -z "$out" ] || { printf '%s\n' "$out"; hit=1; }
done
exit $hit
