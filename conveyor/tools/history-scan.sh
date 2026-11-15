#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# The history scan, for the step that makes a repository public: its whole history and its issues become public.
# Usage: history-scan.sh [--terms <file>] [<repository folder>]   (no folder: the current one)
# Reads every commit of every branch and tag (git log --all) and prints one line per hit, never the matched text:
#   <commit> <path>:<line>: <rule>          a secret (a gitleaks rule) or a private term in a line the commit adds
#   <commit> (message):<line>: <rule>       a private term in the commit's message
#   issue #<number>: <rule>                 a private term in an issue's or pull request's title or text, or in one of
#                                           its comments (gh api; GH_REPO names the repository when its remote does not)
# A private term's rule is "private term (terms file line <n>)", as privacy/check.sh names it; a term matches as
# check.sh matches it: a whole word, case-insensitively, case-sensitively for a `case:` line.
# The terms file is --terms, or the one the host file names (terms; ~/ is the user's home); with neither the scan
# stops, as a scan with no terms would report a clean history it did not check.
# Exit 0 with no hit, 1 with any, 2 when the repository, the terms file or the issues cannot be read or gitleaks fails.
set -uo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
usage() { echo "usage: history-scan.sh [--terms <file>] [<repository folder>]" >&2; exit 2; }
die() { echo "history-scan: $*" >&2; exit 2; }
terms=''
[ "${1:-}" != --terms ] || { [ $# -ge 2 ] || usage; terms=$2; shift 2; }
[ $# -le 1 ] || usage
repo=${1:-.}
if [ -z "$terms" ]; then
  terms=$(jq -r '.terms // empty' "${XDG_CONFIG_HOME:-$HOME/.config}/conveyor/host.json" 2>/dev/null)
  [[ $terms != \~/* ]] || terms=$HOME/${terms#\~/}
fi
[ -n "$terms" ] && [ -r "$terms" ] && [ ! -d "$terms" ] || die "no readable terms file: name one with --terms, or as \"terms\" in the host file"
git -C "$repo" rev-parse --git-dir >/dev/null 2>&1 || die "$repo is not a git repository"
command -v gitleaks >/dev/null || die "gitleaks is not installed"

W=$(mktemp -d) || exit 2; trap 'rm -rf "$W"' EXIT
# The terms as gitleaks rules, one per term, its id the term's line in the file. The expression is grep -w's: the term
# with no word character (letter, digit, _) just before or after it.
n=0
while IFS= read -r t || [ -n "$t" ]; do
  n=$((n + 1))
  case $t in '' | '#'*) continue ;; esac
  ci='(?i)'; case $t in case:*) ci=''; t=${t#case:} ;; esac
  rx=$(printf '%s' "$t" | sed 's/[][\.*^$+?(){}|/]/\\&/g')
  printf "[[rules]]\nid = \"term-%s\"\nregex = '''%s(?:^|[^0-9A-Za-z_])%s(?:\$|[^0-9A-Za-z_])'''\n" "$n" "$ci" "$rx"
done < "$terms" > "$W/terms.toml"

# gitleaks reads the added lines of every commit (git log -p --all). Its exit code is 0 with or without a hit (the
# report says which); any other is a failure. git log -p shows no diff for a merge, so a line added while resolving a
# merge would go unread: each merge is diffed against its first parent, which shows every line the merge brings to
# that line of history (a line from the merged branch is listed again, under the merge). The secrets run uses gitleaks' own rules; the terms run only the terms,
# so the path allowlist of gitleaks' own rules (images, lock files) does not hide a term.
# The repository's own text must not hide a hit, so gitleaks reads a bare mirror of it, which has no .gitleaksignore or
# .gitleaks.toml beside it, with the config always named (-c), and a textconv that turns each "gitleaks:allow" in its
# diffs into "gitleaks;allow" (same lines, so the same line numbers), as gitleaks skips any line that holds the marker.
# $GIT_DIR/info/attributes outranks the commits' .gitattributes, so no file is hidden as binary either.
git clone -q --mirror "$repo" "$W/mirror" 2>"$W/err" || die "the repository cannot be copied: $(head -c 300 "$W/err")"
git -C "$W/mirror" config diff.unallow.textconv "sed 's/gitleaks:allow/gitleaks;allow/g'"
mkdir -p "$W/mirror/info" && echo '* diff=unallow' > "$W/mirror/info/attributes"
printf '[extend]\nuseDefault = true\n' > "$W/secrets.toml"
leaks() { # <report> <config>
  gitleaks detect --no-banner --redact --log-level error --exit-code 0 -s "$W/mirror" -c "$2" \
    --log-opts='--all --full-history --diff-merges=first-parent --textconv' -f json -r "$1" >/dev/null 2>"$W/err" && [ -s "$1" ] \
    || die "gitleaks failed: $(head -c 300 "$W/err")"
}
leaks "$W/secrets.json" "$W/secrets.toml"
out=$(jq -r '.[] | "\(.Commit) \(.File):\(.StartLine): \(.RuleID)"' "$W/secrets.json") || die "the gitleaks report cannot be read"
if [ -s "$W/terms.toml" ]; then
  leaks "$W/terms.json" "$W/terms.toml"
  out+=$'\n'$(jq -r '.[] | "\(.Commit) \(.File):\(.StartLine): private term (terms file line \(.RuleID | ltrimstr("term-")))"' "$W/terms.json") \
    || die "the gitleaks report cannot be read"
fi

# Each commit's message, a file named by its commit, checked by privacy/check.sh; only its private-term hits are kept.
mkdir "$W/msg"
while IFS= read -r -d '' c && IFS= read -r -d '' m; do printf '%s' "$m" > "$W/msg/${c#$'\n'}"; done \
  < <(git -C "$repo" log --all --format='tformat:%H%x00%B%x00')
if [ -n "$(ls "$W/msg")" ]; then
  hits=$(cd "$W/msg" && "$HERE/privacy/check.sh" --terms "$terms" *); [ $? -le 1 ] || die "the privacy check failed on the commit messages"
  out+=$'\n'$(grep ': private term ' <<<"$hits" | sed -E 's/^([0-9a-f]+):/\1 (message):/')
fi

# The issues and pull requests (the issues list holds both) and their comments, one file per text named by its issue
# number; a gh failure stops the scan, as an unread issue is not a clean one.
mkdir "$W/iss"
api() { # <endpoint> <jq filter to [number, text]>
  (cd "$repo" && gh api --paginate "repos/{owner}/{repo}/$1") > "$W/api" 2>"$W/err" \
    || die "the issues cannot be read (gh api $1): $(head -c 300 "$W/err")"
  jq -c ".[] | $2" "$W/api" >> "$W/iss.jsonl" || die "the issues cannot be read (gh api $1 gave no list)"
}
: > "$W/iss.jsonl"
api 'issues?state=all&per_page=100' '[.number, (.title // "") + "\n" + (.body // "")]'
api 'issues/comments?per_page=100' '[(.issue_url | split("/") | last | tonumber), .body // ""]'
api 'pulls/comments?per_page=100' '[(.pull_request_url | split("/") | last | tonumber), .body // ""]'
k=0
while IFS= read -r -d '' num && IFS= read -r -d '' text; do
  k=$((k + 1)); printf '%s\n' "$text" > "$W/iss/$num.$k"
done < <(jq -j '"\(.[0])\u0000\(.[1] | gsub("\u0000"; ""))\u0000"' "$W/iss.jsonl")
if [ -n "$(ls "$W/iss")" ]; then
  hits=$(cd "$W/iss" && "$HERE/privacy/check.sh" --terms "$terms" *); [ $? -le 1 ] || die "the privacy check failed on the issues"
  out+=$'\n'$(grep ': private term ' <<<"$hits" | sed -E 's/^([0-9]+)\.[0-9]+:[0-9]+: /issue #\1: /' | sort -u)
fi

out=$(grep -v '^$' <<<"$out" | sort -u)
[ -z "$out" ] && exit 0
printf '%s\n' "$out"; exit 1
