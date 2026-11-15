# Lanes

A lane is a worktree of the project for work outside the belt.

- **Fast lane**, the owner's own worktree for a change made by hand. `conveyor.sh lane fast create` makes it. The fast
  lane never pushes. `lane fast review` previews its change with the card reviewer. `lane fast land` lands it as one
  card, reviewed and tested as any card is. `lane fast reset` sets the lane to main once that card has landed. Only the
  owner can land and reset: both refuse in a Foreman session and inside a card.
- **Research lane**, read-only. `conveyor.sh lane research create` makes a worktree whose shell runs every command in
  an operating-system sandbox, with no network. The sandbox can write only `reports/`, the lane's own folder and the
  temp folder. The lane files issues only through its own filing command, and they stay held until the owner releases
  them (`conveyor/README.md`, Research lane).
