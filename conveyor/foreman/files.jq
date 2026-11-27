# SPDX-License-Identifier: Apache-2.0
# True when a Bash hook input's command files an issue (foreman.sh files says how it is read); run with jq -e.
# foreman.sh files and the plugin's filing and filed hook lines (filing-hook.sh) both read it.
# With --arg strict 1 (foreman.sh filed, for an output that links no issue) it keeps only what shows a filing: a quoted text
# with a space in it is read as one word, its spaces turned to _ and its other characters kept (a search for 'gh issue' or a
# title that says -X PATCH is no command, and a mutation in quotes still shows createIssue), a word that holds $ or a
# backtick after `issue` alone could be a search pattern, and a `gh api` call with -X PATCH edits an issue and files none,
# so none of them counts.
def strict: ($ARGS.named.strict // "") != "";
def flags: "(?>\\s+-(-[^\\s=]*(=\\S*|\\s+[^-\\s]\\S*)?|[^-\\s](\\s+[^-\\s]\\S*)?(?=\\s)|[^-\\s]\\S+))*";
def vword: if strict then "(?!)" else "(?!-)\\S*[$`]" end;
def masked: if strict then gsub("\\\\\n"; "") | gsub("(?<q>'[^']*'|\"[^\"]*\")"; .q | gsub("\\s"; "_")) else . end;
def unedits: if strict then [splits("[;&|\n]")] | map(select(test("\\bgh(-write)?\(flags)\\s+api(\\s+\\S+)*?\\s+(-X\\s*|--method[=\\s]\\s*)(?i:PATCH)\\b") | not)) | join(";") else . end;
def writes: test("(?i:\\bpost\\b)|\\s-(-(data|json|form|upload-file|body)|[a-zA-Z]*[dFT])");
def hex: ascii_downcase | explode | reduce .[] as $c (0; . * 16 + if $c >= 97 then $c - 87 else $c - 48 end);
.tool_input.command // "" | gsub("\\\\u(?<u>[0-9a-fA-F]{4})|\\\\x(?<x>[0-9a-fA-F]{2})|%(?<p>[0-9a-fA-F]{2})"; [.u // .x // .p | hex] | implode)
| masked
| gsub("\\$?[\"\u0027]|\\\\"; "")
| unedits
| test("\\b(issue(?>\\s+-(-[^\\s=]*(=\\S*|\\s+[^-\\s]\\S*)?|[^-\\s](\\s+[^-\\s]\\S*)?(?=\\s)|[^-\\s]\\S+))*\\s+((create|new)\\b|\(vword))|gh(-write)?\(flags)\\s+issue\(flags)\\s+(?!-)\\S*[$`]|gh(-write)?(?>\\s+-(-[^\\s=]*(=\\S*|\\s+[^-\\s]\\S*)?|[^-\\s](\\s+[^-\\s]\\S*)?(?=\\s)|[^-\\s]\\S+))*\\s+(?!-)\\S*[$`]|gh(-write)?(?>\\s+-(-[^\\s=]*(=\\S*|\\s+[^-\\s]\\S*)?|[^-\\s](\\s+[^-\\s]\\S*)?(?=\\s)|[^-\\s]\\S+))*\\s+api\\s[^;&|\\n]*(\\bissues(?![/\\w-])|createIssue|=@|--input\\b|[$`]))")
  or test("repos/[^/\\s]+/[^/\\s]+/issues(?![/\\w.-])|/graphql(?![/\\w.-])")
  or ([splits("[;&|\\n]")] | any(test("\\bcurl\\b.*\\s(-[a-zA-Z]*K|--config\\b)") or test("\\bwget\\b.*\\s(-[a-zA-Z]*[ie]|--(config|input-file|execute)\\b)")
    or (test("\\b(curl|wget)\\b") and test("[$`]") and writes)))
