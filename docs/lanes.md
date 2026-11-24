# Lanes

A lane is a worktree of the project for work outside the belt.

`/conveyor-belt:setup` asks if you want a fast lane and a research lane. On yes, it makes the lane. You can also make a
lane later with its `create` command, below. A lane that is already there stays as it is.

- **Fast lane**, the owner's own worktree for a change made by hand. `conveyor.sh lane fast create` makes it. The fast
  lane never pushes. `lane fast review` previews its change with the card reviewer. `lane fast land` lands it as one
  card, reviewed and tested as any card is. `lane fast reset` sets the lane to main once that card has landed. Only the
  owner can land and reset: both refuse in a Foreman session and inside a card.
- **Research lane**, read-only. `conveyor.sh lane research create` makes a worktree whose shell runs every command in
  an operating-system sandbox, with no network. The sandbox can write only `reports/`, the lane's own folder and the
  temp folder. The lane files issues only through its own filing command, and they stay held until the owner releases
  them (`conveyor/README.md`, Research lane).

## Send a message to the Foreman

A session in a lane can send a message to the project's Foreman: a finding, a question, or a card to file or watch.
The session's start tells it the command.

- In the fast lane: `conveyor.sh lane fast tell '<message>'`. It works only in the fast lane's checkout.
- In the research lane: `research-file --tell '<message>'`. The lane's shell has no network, so this command is the
  way out.

The message comes to the Foreman in its next wake, as one line that names the lane. When no Foreman runs, it comes at
the Foreman's next start. A message is one line. A long message is refused: write a report and send its path.
