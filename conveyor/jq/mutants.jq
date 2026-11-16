# SPDX-License-Identifier: Apache-2.0
# The mutants of one source file (lib/mutate.sh mutsample()): plain text rules, one line each, no parser. Input: the
# file's lines (jq -Rn, inputs); $kind: sh (a shell file) or js (JavaScript or TypeScript). Output: each mutant,
# {line (from 1), kind, before (the line), after (the line changed)}, one a line. A line has at most one mutant of each
# kind, made at the first place the rule finds; a comment line has none. The kinds:
#   flip    a comparison flipped: < and >=, > and <=, == and !=, === and !== (js); -lt and -ge, -gt and -le, -eq
#           and -ne, == and != (sh); only with a space on each side, so an arrow, a generic or a redirect is left
#   negate  a condition negated: `if (c)` becomes `if (!(c))` (js); `if c` and `elif c` become `if ! c` (sh). A loop's
#           condition is left: negated it would most often loop until the time limit
#   number  a number constant one more: a whole number, not part of a name or of $1, 2>&1 or 1.5
#   andor   && and || swapped, with a space on each side
#   delete  a call statement deleted: a line that is a whole call; its line stays, as `;` (js) or `:` (sh)
def flips: if $kind == "sh" then {"-lt": "-ge", "-ge": "-lt", "-gt": "-le", "-le": "-gt", "-eq": "-ne", "-ne": "-eq", "==": "!=", "!=": "=="}
  else {"===": "!==", "!==": "===", "==": "!=", "!=": "==", "<": ">=", ">=": "<", ">": "<=", "<=": ">"} end;
def fliprule: if $kind == "sh" then "(?<= )(-lt|-ge|-gt|-le|-eq|-ne|==|!=)(?= )" else "(?<= )(===|!==|==|!=|<=|>=|<|>)(?= )" end;
def numrule: if $kind == "sh" then "(?<![\\w$.&<>{-])[0-9]+(?![\\w.<>])" else "(?<![\\w$.-])[0-9]+(?![\\w.])" end;
def comment: if $kind == "sh" then test("^\\s*#") else test("^\\s*(//|/\\*|\\*)") end;
def count($re): [scan($re)] | length;
def balanced: count("\\(") == count("\\)");
def swapped($m; $map): .[:$m.offset] + $map[$m.string] + .[$m.offset + $m.length:];
# The words a shell line may start with that are no call of a command (or whose deletion leaves a block unclosed).
def shwords: ["if", "then", "else", "elif", "fi", "for", "while", "until", "do", "done", "case", "esac", "function", "return",
  "local", "declare", "typeset", "export", "readonly", "set", "shift", "exit", "break", "continue", "in", "select", "time",
  "unset", "trap", "eval", "exec", "source", "wait", "true", "false"];
def jswords: ["if", "for", "while", "switch", "return", "function", "catch", "typeof", "new", "delete", "throw", "yield", "super", "class", "import", "export"];
def deleted:
  if $kind == "sh" then
    capture("^(?<i>\\s*)(?<n>[A-Za-z_][A-Za-z0-9_-]*)(?<r>( .*)?)$") as $c
    | select(($c.n | IN(shwords[]) | not) and (test("(\\\\|\\||&&|\\{|\\(|<<)\\s*$|<<|[;&]\\s*(then|do)\\b") | not)
        and count("\"") % 2 == 0 and count("'") % 2 == 0) | $c.i + ":"
  else
    capture("^(?<i>\\s*)(await\\s+)?(?<n>[A-Za-z_$][\\w$]*)(\\s*\\.\\s*[A-Za-z_$][\\w$]*)*\\s*\\(.*\\)\\s*;?\\s*$") as $c
    | select(($c.n | IN(jswords[]) | not) and balanced) | $c.i + ";"
  end;
def mutants:
  . as $l
  | (first(match(fliprule)) as $m | {kind: "flip", after: ($l | swapped($m; flips))}),
    (if $kind == "sh" then capture("^(?<i>\\s*)(?<k>if|elif) (?<r>.*)$") | select(.r | startswith("!") | not) | {kind: "negate", after: "\(.i)\(.k) ! \(.r)"}
     else capture("^(?<i>\\s*(\\}\\s*else\\s+)?)if \\((?<c>.*)\\)(?<e>\\s*\\{?\\s*)$") | select(.c | balanced) | {kind: "negate", after: "\(.i)if (!(\(.c)))\(.e)"} end),
    (first(match(numrule)) | select(.length <= 15) | {kind: "number", after: ($l[:.offset] + ((.string | tonumber) + 1 | tostring) + $l[.offset + .length:])}),
    (first(match("(?<= )(&&|\\|\\|)(?= )")) as $m | {kind: "andor", after: ($l | swapped($m; {"&&": "||", "||": "&&"}))}),
    (deleted | {kind: "delete", after: .});
[inputs] | to_entries[] | (.key + 1) as $n | .value as $l | select($l | comment | not) | $l | mutants
  | select(.after != $l) | {line: $n, kind, before: $l, after}
