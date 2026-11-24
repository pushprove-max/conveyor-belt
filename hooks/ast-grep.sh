#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# The plugin's SessionStart hook for ast-grep (hooks/hooks.json): in a project with a tracked file (git ls-files) in a
# language ast-grep parses, and with ast-grep installed (the plugin's bin/ast-grep runs), it prints one line, which
# Claude Code adds to the session's context: ast-grep is there, how to call it, and the project's languages by
# the names its -l takes. Otherwise it prints nothing. It runs from the plugin, so in any project, and never fails:
# its exit is 0 and it writes nothing to stderr.
# A language is known by the file extensions of ast-grep's language registry, as the pinned version (ast-grep-cli
# 0.51.3, .claude/scripts/requirements.txt) has it: crates/language/src/registry.rs. Each one counts, Markdown, JSON
# and YAML too, as ast-grep searches them all.
top=${CLAUDE_PROJECT_DIR:-.}
"$(dirname "${BASH_SOURCE[0]}")/../bin/ast-grep" --version >/dev/null 2>&1 || exit 0
langs=$(git -C "$top" ls-files -z 2>/dev/null | tr '\0' '\n' | awk -F/ '
  BEGIN {
    split("bash:bash bats:bash cgi:bash command:bash env:bash fcgi:bash ksh:bash sh:bash tmux:bash tool:bash zsh:bash " \
      "c:c h:c cc:cpp hpp:cpp cpp:cpp c++:cpp hh:cpp cxx:cpp cu:cpp ino:cpp cs:csharp css:css scss:css dart:dart " \
      "ex:elixir exs:elixir go:go hs:haskell hcl:hcl nomad:hcl tf:hcl tfvars:hcl workflow:hcl html:html htm:html " \
      "xhtml:html java:java cjs:javascript js:javascript mjs:javascript jsx:javascript json:json kt:kotlin " \
      "ktm:kotlin kts:kotlin lua:lua markdown:markdown md:markdown nix:nix php:php py:python py3:python pyi:python " \
      "bzl:python bazel:python rb:ruby rbw:ruby gemspec:ruby rs:rust scala:scala sc:scala sbt:scala sol:solidity " \
      "swift:swift tsx:tsx ts:typescript cts:typescript mts:typescript yaml:yaml yml:yaml zig:zig", m, " ")
    for (i in m) { split(m[i], p, ":"); L[p[1]] = p[2] }
  }
  # The extension is what follows the last dot, with a character before that dot: a file named .env has none.
  match($NF, /[^.]\.[^.]+$/) { e = substr($NF, RSTART + 2); if (e in L) S[L[e]] = 1 }
  END { for (k in S) print k }' | sort | paste -sd, - | sed 's/,/, /g')
[ -n "$langs" ] || exit 0
echo "ast-grep is installed: a code search that matches syntax, not text. Call it as ast-grep run -p '<pattern>' -l <lang> [<path>...]. Languages in this project: $langs."
exit 0
