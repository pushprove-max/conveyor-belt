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
# The stack .k holds the open contexts: s and d quotes, c for (, C for $(, b for a backtick, B for an escaped backtick (\`)
# inside a backtick command, which only another \` ends (a \` in a b opens a B), a for a case up to its esac (a ) that
# ends a case pattern ends no substitution), h for a # comment (a # that starts a word, out of quotes; quotes in it open
# nothing, and it ends at the line's end or at the backtick it is in, where a backslash makes the next character text, so
# \` does not end it; bash skips it, so scan drops its text); none open is the command itself. .p is the last character,
# but "a" after the ) of a $( or a closing backtick: the word goes on there, so a # after one is text, not a comment. A
# backslash and a newline out of single quotes and comments are a line continuation: bash removes both, so .p stays the
# character before them. In a comment out of backticks the newline still ends it, as it does in bash; in a backtick bash
# removes the pair before it reads the comment, so the comment goes on. An escape (\u, \x or %, as decoded reads it) is
# text in the word it is in: scan decodes it there, and what it gives opens no quote or comment, so a %20 in a URL does
# not make the # after it start a comment.
def hex: ascii_downcase | explode | reduce .[] as $c (0; . * 16 + if $c >= 97 then $c - 87 else $c - 48 end);
def esc: "\\\\u(?<u>[0-9a-fA-F]{4})|\\\\x(?<x>[0-9a-fA-F]{2})|%(?<p>[0-9a-fA-F]{2})";
def decoded: gsub(esc; [.u // .x // .p | hex] | implode);
def scan: reduce (match("\(esc)|(?s:.)"; "g").string) as $c ({o: [], k: [], e: false, p: ""};
  (.k[-1] // "") as $t | ($c | test("\\s")) as $w
  | if ($c | length) > 1 then (if $t == "h" then . else ($c | decoded) as $d
      | .o += [if ($d | test("\\s")) and ($t == "s" or $t == "d") then "_" else $d end] | .p = "a" end) | .e = false
    elif .e then (if $c == "\n" and $t != "h" then . else (if $c == "`" and $t != "h" and any(.k[]; . == "b") then (if $t == "B" then .k |= .[:-1] else .k += ["B"] end) else . end)
      | .o += [if $t == "h" then empty elif $w and ($t == "s" or $t == "d") then "_" else $c end]
      | .p = (if $c == "$" and any(.k[]; . == "b") then "$" else "\\" end) end) | .e = false
    elif $t == "h" then (if $c == "\n" then .k |= .[:-1] | .o += [$c] | .p = $c elif .k[-2] != "b" then . elif $c == "\\" then .e = true
      elif $c == "`" then .k |= .[:-2] | .o += [$c] | .p = "a" else . end)
    elif $t == "s" then (if $c == "\u0027" then .k |= .[:-1] else . end) | .o += [if $w then "_" else $c end] | .p = $c
    elif $t == "d" then (if $c == "\\" then .e = true elif $c == "\"" then .k |= .[:-1] elif $c == "`" then .k += ["b"]
      elif $c == "(" and .p == "$" then .k += ["C"] else . end) | .o += [if $w then "_" else $c end] | .p = (if $c == "\\" then .p else $c end)
    elif $c == "#" and (.p | test("^$|[\\s;&|()<>`]")) then .k += ["h"] | .p = $c
    else (if $t == "a" and ($c | test("[\\s;&|)`]")) and (.o | join("") | test("(^|[;&|()`\\n]|\\bin\\s)\\s*esac$")) then .k |= .[:-1] else . end)
      | (.k[-1] // "") as $t
      | (if $c == "\\" then .e = true elif $c == "\u0027" then .k += ["s"] elif $c == "\"" then .k += ["d"]
      elif $c == "`" then (if $t == "b" then .k |= .[:-1] else .k += ["b"] end) elif $c == "(" then .k += [if .p == "$" then "C" else "c" end]
      elif $c == ")" and ($t == "c" or $t == "C") then .k |= .[:-1]
      elif $w and (.o | join("") | test("(^|[;&|()`{!\\n]|\\b(do|then|else|if|elif|while|until|time)\\s)\\s*case$")) then .k += ["a"] else . end) | .o += [$c]
      | .p = (if ($c == "`" and $t == "b") or ($c == ")" and $t == "C") then "a" elif $c == "\\" then .p else $c end)
    end) | .o | join("");
def masked: if strict then scan else decoded end;
def unedits: if strict then [splits("[;&|\n]")] | map(select(test("\\bgh(-write)?\(flags)\\s+api(\\s+\\S+)*?\\s+(-X\\s*|--method[=\\s]\\s*)(?i:PATCH)\\b") | not)) | join(";") else . end;
def writes: test("(?i:\\bpost\\b)|\\s-(-(data|json|form|upload-file|body)|[a-zA-Z]*[dFT])");
.tool_input.command // "" | masked
| gsub("\\$?[\"\u0027]|\\\\"; "")
| unedits
| test("\\b(issue(?>\\s+-(-[^\\s=]*(=\\S*|\\s+[^-\\s]\\S*)?|[^-\\s](\\s+[^-\\s]\\S*)?(?=\\s)|[^-\\s]\\S+))*\\s+((create|new)\\b|\(vword))|gh(-write)?\(flags)\\s+issue\(flags)\\s+(?!-)\\S*[$`]|gh(-write)?(?>\\s+-(-[^\\s=]*(=\\S*|\\s+[^-\\s]\\S*)?|[^-\\s](\\s+[^-\\s]\\S*)?(?=\\s)|[^-\\s]\\S+))*\\s+(?!-)\\S*[$`]|gh(-write)?(?>\\s+-(-[^\\s=]*(=\\S*|\\s+[^-\\s]\\S*)?|[^-\\s](\\s+[^-\\s]\\S*)?(?=\\s)|[^-\\s]\\S+))*\\s+api\\s[^;&|\\n]*(\\bissues(?![/\\w-])|createIssue|=@|--input\\b|[$`]))")
  or test("repos/[^/\\s]+/[^/\\s]+/issues(?![/\\w.-])|/graphql(?![/\\w.-])")
  or ([splits("[;&|\\n]")] | any(test("\\bcurl\\b.*\\s(-[a-zA-Z]*K|--config\\b)") or test("\\bwget\\b.*\\s(-[a-zA-Z]*[ie]|--(config|input-file|execute)\\b)")
    or (test("\\b(curl|wget)\\b") and test("[$`]") and writes)))
