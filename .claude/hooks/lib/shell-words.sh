#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Shell-text readers shared by bash-guardrails.sh and mac-test-refusal.sh: split_search_segments, seg_words,
# load_words and shq. Sourced, never run; nothing here expands or runs the text it reads.

# Split a command line into segments at `;`, `&`, `|` and newlines, one per
# line, each prefixed 1 when it reads a pipe, 2 when it is the `||` alternative
# of the segment before, 3 when it follows `&&` (it may never run), and 0 otherwise. Quotes count only
# for segment boundaries (`rg 'a|b' src` is one segment). `$2 = \0` ends each
# segment with NUL instead, for a reader that must keep a multi-line quote whole.
split_search_segments() {
  local TEXT=$1 SEG="" QUOTE="" CHAR NEXT PIPE=0 I END=${2:-\\n} OP="" # OP = the last char if it is an unescaped, unquoted < or >
  for ((I=0; I<${#TEXT}; I++)); do
    CHAR=${TEXT:I:1}; NEXT=${TEXT:I+1:1}
    # A backslash escapes the next character everywhere except inside single
    # quotes, so `"[^ \"]*|b"` stays one quoted span and its `|` is pattern
    # text, not a pipe. Without this the escaped quote closed the span early.
    if [ "$CHAR" = '\' ] && [ "$QUOTE" != "'" ]; then SEG+=$CHAR$NEXT; I=$((I+1)); OP=""; continue; fi
    if [ -n "$QUOTE" ]; then SEG+=$CHAR; [ "$CHAR" = "$QUOTE" ] && QUOTE=""; continue; fi
    case "$CHAR" in
      "'"|'"') QUOTE=$CHAR; SEG+=$CHAR; OP="" ;;
      '|') [ "$OP" = '>' ] && { SEG+=$CHAR; OP=""; continue; } # `>|` is the clobber redirect
           printf "%s%s$END" "$PIPE" "$SEG"; SEG=""; PIPE=1
           if [ "$NEXT" = '|' ]; then PIPE=2; I=$((I+1)); elif [ "$NEXT" = '&' ]; then I=$((I+1)); fi ;;
      '&'|';'|$'\n')
        # `2>&1`, `>&2` and `&>` are redirections, not a background `&`: cutting
        # there made `cmd 2>&1 | jq` read as a stray `1` piped into jq.
        if [ "$CHAR" = '&' ] && { [ -n "$OP" ] || [ "$NEXT" = '>' ]; }; then SEG+=$CHAR; OP=""; continue; fi
        printf "%s%s$END" "$PIPE" "$SEG"; SEG=""; PIPE=0
        [ "$CHAR$NEXT" = '&&' ] && { PIPE=3; I=$((I+1)); } ;;
      *) SEG+=$CHAR; OP=${CHAR//[!<>]/} ;;
    esac
  done
  printf "%s%s$END" "$PIPE" "$SEG"
}

# Split one segment into words the way the shell would, expanding nothing:
# quotes group and are removed, and a backslash escapes as it does in bash.
# Deleting every quote and splitting on spaces turned `rg 'foo bar' src` into
# a pattern plus a stray `bar` path. An unquoted `>` also ends a word unless an
# fd number, `&`, `<` or `>` leads it: `foo>src/x` is `foo` plus a redirect.
seg_words() {
  local TEXT=$1 W="" QUOTE="" HAVE=0 CHAR NEXT I
  for ((I=0; I<${#TEXT}; I++)); do
    CHAR=${TEXT:I:1}; NEXT=${TEXT:I+1:1}
    if [ "$CHAR" = '\' ] && [ "$QUOTE" != "'" ]; then
      HAVE=1
      if [ "$QUOTE" = '"' ] && [[ $NEXT != [\"\\\$\`] ]]; then W+=$CHAR; else W+=$NEXT; I=$((I+1)); fi
      continue
    fi
    if [ -n "$QUOTE" ]; then
      if [ "$CHAR" = "$QUOTE" ]; then QUOTE=""; else W+=$CHAR; fi
      continue
    fi
    case "$CHAR" in
      "'"|'"') QUOTE=$CHAR; HAVE=1 ;;
      ' '|$'\t') [ "$HAVE" = 1 ] && printf '%s\n' "$W"; W=""; HAVE=0 ;;
      '>') [[ $HAVE = 1 && ! $W =~ ^([0-9]*|&)$ && $W != *[\<\>] ]] && { printf '%s\n' "$W"; W=""; }; W+=$CHAR; HAVE=1 ;;
      *) W+=$CHAR; HAVE=1 ;;
    esac
  done
  [ "$HAVE" = 1 ] && printf '%s\n' "$W"
}

# WORDS = the segment's words, minus a leading `(`/`{` and the shell keywords
# that open a compound command, so `do rg x` and `(curl ...` read as the tool.
load_words() {
  mapfile -t WORDS < <(seg_words "$1")
  while [ ${#WORDS[@]} -gt 0 ]; do
    WORDS[0]=${WORDS[0]#"${WORDS[0]%%[!({]*}"}
    case "${WORDS[0]}" in
      ''|do|then|else|elif|if|while|until|'!') WORDS=("${WORDS[@]:1}") ;;
      # Bash's `time` keyword takes `-p`, then `--`: neither is the command.
      time) WORDS=("${WORDS[@]:1}"); [ "${WORDS[0]-}" = -p ] && WORDS=("${WORDS[@]:1}")
            [ "${WORDS[0]-}" = -- ] && WORDS=("${WORDS[@]:1}") ;;
      *) break ;;
    esac
  done
}

shq() { printf "'%s'" "${1//\'/\'\\\'\'}"; }
