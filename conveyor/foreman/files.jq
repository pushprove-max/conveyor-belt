# SPDX-License-Identifier: Apache-2.0
# True when a Bash hook input's command files an issue (foreman.sh files says how it is read); run with jq -e.
# foreman.sh files and the plugin's filing and filed hook lines (filing-hook.sh) both read it.
# With --arg strict 1 (foreman.sh filed, for an output that links no issue) it keeps only what shows a filing: a quoted text
# with a space in it is read as one word, its spaces turned to _ and its other characters kept (a search for 'gh issue' or a
# title that says -X PATCH is no command, and a mutation in quotes still shows createIssue), except a command substitution
# ($(...) or backticks, at any depth and with parentheses in its own quotes) inside double quotes, which runs and is read
# as a command (scan reads the quotes as bash nests them; a backslash makes the next character text, except \` and \$ inside
# a backtick command, which bash reads as ` and $ when it reads that command, so they nest), a word that holds $ or a
# backtick after `issue` alone could be a search pattern, and a `gh api` call with -X PATCH edits an issue and files none,
# so none of them counts.
def strict: ($ARGS.named.strict // "") != "";
def flags: "(?>\\s+-(-[^\\s=]*(=\\S*|\\s+[^-\\s]\\S*)?|[^-\\s](\\s+[^-\\s]\\S*)?(?=\\s)|[^-\\s]\\S+))*";
def vword: if strict then "(?!)" else "(?!-)\\S*[$`]" end;
# The stack .k holds the open contexts: s and d quotes, c for ( or $(, b for a backtick, B for an escaped backtick (\`)
# inside a backtick command, which only another \` ends (a \` in a b opens a B), a for a case up to its esac (a ) that
# ends a case pattern ends no substitution); none open is the command itself.
def scan: reduce (explode[] | [.] | implode) as $c ({o: [], k: [], e: false, p: ""};
  (.k[-1] // "") as $t | ($c | test("\\s")) as $w
  | if .e then (if $c == "`" and any(.k[]; . == "b") then (if $t == "B" then .k |= .[:-1] else .k += ["B"] end) else . end)
      | .o += [if $w and ($t == "s" or $t == "d") then "_" else $c end] | .e = false
      | .p = (if $c == "$" and any(.k[]; . == "b") then "$" else "" end)
    elif $t == "s" then (if $c == "\u0027" then .k |= .[:-1] else . end) | .o += [if $w then "_" else $c end] | .p = $c
    elif $t == "d" then (if $c == "\\" then .e = true elif $c == "\"" then .k |= .[:-1] elif $c == "`" then .k += ["b"]
      elif $c == "(" and .p == "$" then .k += ["c"] else . end) | .o += [if $w then "_" else $c end] | .p = $c
    else (if $t == "a" and ($c | test("[\\s;&|)`]")) and (.o | join("") | test("(^|[;&|()`\\n]|\\bin\\s)\\s*esac$")) then .k |= .[:-1] else . end)
      | (.k[-1] // "") as $t
      | (if $c == "\\" then .e = true elif $c == "\u0027" then .k += ["s"] elif $c == "\"" then .k += ["d"]
      elif $c == "`" then (if $t == "b" then .k |= .[:-1] else .k += ["b"] end) elif $c == "(" then .k += ["c"]
      elif $c == ")" and $t == "c" then .k |= .[:-1]
      elif $w and (.o | join("") | test("(^|[;&|()`{!\\n]|\\b(do|then|else|if|elif|while|until|time)\\s)\\s*case$")) then .k += ["a"] else . end) | .o += [$c] | .p = $c
    end) | .o | join("");
def masked: if strict then gsub("\\\\\n"; "") | scan else . end;
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
