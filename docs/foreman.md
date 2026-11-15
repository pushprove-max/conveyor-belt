# Foreman

The Foreman is a Claude Code session in a project's main checkout. It watches that project's Conveyor and brings you
what needs you: blocked cards, changes that wait for your yes, stuck cards and push errors. There is one Foreman per
project.

## Start it

Set it up once with `/conveyor-belt:setup --foreman`. Then type `/conveyor-belt:foreman` in a session in the main
checkout. You can also say "start your role" (or "you are the Foreman") as the whole message. These words do nothing in
a worktree, or in a checkout that is not a Conveyor project.

A new session in the main checkout takes the role when no session holds it, or when the session that holds it is gone.
When a live session holds it, the new session asks you whether to take it over (`conveyor/README.md`, Foreman).
The session that takes the role says so in one line: `This session is now the Foreman: …`. When the host file gives
the Foreman a name in `foreman.name`, the line shows it in brackets: `This session is now the Foreman (Ada): …`.
`/conveyor-belt:foreman off` ends the role.

## The Foreman on your own machine

The Foreman can run on your own machine while the belt runs on a host. Give your machine's host file (its
settings file, `~/.config/conveyor/host.json`) the host's `ssh` target and the project's record as the host has it:

```json
{"ssh": "devhost", "records": [{"repo": "shop", "main": "/srv/repos/shop"}]}
```

A checkout here whose `origin` remote is that repo gets that record, even when its path is different. The Foreman then
asks the host about the record over ssh. Open decisions in the host's ledger show as unavailable.

## Away and auto

- `/conveyor-belt:away`: the owner is away. The Foreman works by the owner's own away rules, the file that the host
  file names as `foreman.away`.
- `/conveyor-belt:auto on | narrow | off`: the Foreman decides the owner's open decisions (the Board's ledger) for
  them, by their recorded way of deciding. It logs each decision with its question, pick, reason and whether it can be
  reversed, in `<state folder>/auto/<date>-<time>.md`. `on` decides every open decision that has a recommended option.
  `narrow` decides only formalities: an answer the owner already gave to the same question. It never decides what the
  pack's `auto.reserved` holds (the pack is the project's settings, `.conveyor/project.json`; by default production deploys, deletes, new feature flags, security and password
  settings, configured product values, and licence or consent questions). Those are listed under "Waiting for the
  owner". A band above the prompt shows whether auto is on.
