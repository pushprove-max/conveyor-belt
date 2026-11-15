---
description: Foreman mode, the owner is away: work by the owner's own away rules (Conveyor Belt ships none)
allowed-tools: Bash, Read
---

The owner is away. This is for the Foreman session (`/conveyor-belt:foreman`); in any other session, say so and stop.

1. Read the host file, `${XDG_CONFIG_HOME:-$HOME/.config}/conveyor/host.json`, for `foreman.away`: the file of the
   owner's away rules (a path starting `~/` is under the home folder).
2. When it names a readable file, read it and follow those rules until the owner is back; reply with one line naming
   the file. When it names none, or the file cannot be read, reply that there are no away rules (Conveyor Belt ships
   none; the owner writes their own and names the file as `foreman.away` in the host file), and change nothing in how
   you work.
