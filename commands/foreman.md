---
description: Foreman mode, make this session the Foreman of this project (one per project; it stays the Foreman when continued, resumed or cleared with /clear), or end the role with off
argument-hint: "[off]"
allowed-tools: Bash
---

Run from the main checkout this session runs in. The arguments given were: `$ARGUMENTS`.

- When they are `off`, run `"${CLAUDE_PLUGIN_ROOT}/shim.sh" conveyor/foreman/foreman.sh off` and reply with its one
  line.
- Otherwise run `CLAUDE_PLUGIN_OPTION_boardAutoOpen='${user_config.boardAutoOpen}' "${CLAUDE_PLUGIN_ROOT}/shim.sh" conveyor/foreman/foreman.sh claim ${CLAUDE_SESSION_ID}`.
  When it succeeds, its first line says this session is now the Foreman: reply with that one line, and with the line
  that says the Board is not running and is started when there is one, and with the line on the prompt cache time when there is one. From now on work by the rest of its output, your rules and
  saved state as the Foreman. When it fails, show its message and stop.

When you file several issues at once, read them beside each other and beside the cards on the belt (picked and not
landed, closed or blocked) before you file them. Where two clearly change the same part of the same file, for example
both naming one function, one test file or one panel, write a `Depends on: #N` line into the later one's body yourself,
naming the earlier issue or the card's issue. Sharing an area, a folder or README.md is not enough. The engine makes
the same check before it picks an issue, but a line you write saves that call and keeps the clash from being built at
all.
