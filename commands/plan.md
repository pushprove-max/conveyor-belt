---
description: Pick the best skill of Matt Pocock's skills (mattpocock-skills), or an ordered sequence of them, for what you want to do, and say exactly what to type. It only recommends. By Max Goldfarb.
argument-hint: "What do you want to do?"
allowed-tools: Bash, Read
disable-model-invocation: true
---

# plan

Recommend which `mattpocock-skills` skills fit the prompt in `$ARGUMENTS` (if empty, use the current conversation).
Recommend only; do not start the work.

## Steps

1. Read the router map. It is the source of truth for the flows, so read it every time instead of relying on memory.
   Its folder is the install path Claude Code records for `mattpocock-skills@claude-plugins-official`:

       jq -r '.plugins["mattpocock-skills@claude-plugins-official"][0].installPath // empty' "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/installed_plugins.json"

   The map is `skills/engineering/ask-matt/SKILL.md` under that folder. The installed skill list in your context has
   each skill's one-line description. If the plugin is not installed or the map is missing, say that this command
   needs Matt Pocock's skills, give the install command `claude plugin install mattpocock-skills@claude-plugins-official`
   (or `/conveyor-belt:setup`, which installs it), and stop.
2. Classify the prompt against the map: main flow (idea to ship), an on-ramp (triage, diagnosing-bugs, wayfinder),
   codebase health, or standalone. Size it: one session or multi-session? Is there a repo under it?
3. If the pick includes a tracker-based skill (to-spec, to-tickets, triage, implement, wayfinder) and
   `docs/agents/issue-tracker.md` does not exist in this repo, put `/mattpocock-skills:setup-matt-pocock-skills`
   first.
4. If the current repo already has its own skill or workflow for the same job, name it as the alternative in one
   line. Do not pick between them silently.

## Output

- **Pick:** the ordered skill sequence. For each step: the exact command (`/mattpocock-skills:<name> <suggested
  argument>`) and one line on why.
- **Type first:** the one command to run now.
- **Not chosen:** at most two close alternatives and why they lost.
- **Context tip:** only if the map's context-hygiene or phase-boundary advice changes what the user should do (for
  example, keep grill, spec and tickets in one window).

If the prompt is too vague to classify, ask ONE question and say which skill each answer leads to.
