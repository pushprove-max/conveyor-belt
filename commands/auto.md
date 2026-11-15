---
description: Foreman mode, the owner's open decisions decided for them by their recorded way of deciding, each logged with its reasons: on (the owner is away), narrow (decide only formalities) or off; with no argument, its status. By Max Goldfarb.
argument-hint: "on | narrow | off"
allowed-tools: Bash, Read
---

This is for the Foreman session (`/conveyor-belt:foreman`), in the project's main checkout; in any other session, say
so and stop. The arguments given were: `$ARGUMENTS`.

- `on`, `narrow` or `off`: run `"${CLAUDE_PLUGIN_ROOT}/shim.sh" conveyor/conveyor.sh auto <that word>` and reply with
  its line. With no argument, run it with `status` instead.
- After `on` or `narrow` succeeds, run `"${CLAUDE_PLUGIN_ROOT}/shim.sh" conveyor/conveyor.sh auto rules` and work by
  its output until the owner runs `/conveyor-belt:auto off`: start with its decide step now, and say in one line what
  it decided and what it left for the owner.
- After `off`, put every decision to the owner again, and give them a short account of what was decided while it was
  on, from the log its line names.

What is never decided for the owner is the pack's `auto.reserved` (by default: production deploys, deletes, new
feature flags, security and password settings, configured product values, licence or consent questions). The band
above the prompt shows whether it is on.
